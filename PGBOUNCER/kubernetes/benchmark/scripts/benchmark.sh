#!/bin/sh
set -e

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "Error: FLOW_ID, API_KEY, and BENCHMARK_TYPE (hey|locust) arguments are required!" >&2
  exit 1
fi

FLOW_ID=$1
API_KEY=$2
BENCHMARK_TYPE=$3
FIXED_WORKER_COUNT=$4


export LANGFLOW_SERVER_URL="http://langflow:7860"
FAILURE_THRESHOLD=5

check_workers() {
  echo "--------------------------------------------------------------------"
  echo "--- Checking Langflow worker status ---"
  echo "--------------------------------------------------------------------"
  CONFIGURED_WORKERS="$(kubectl get configmap langflow-config -o jsonpath='{.data.WEB_CONCURRENCY}' 2>/dev/null || true)"
  [ -n "$CONFIGURED_WORKERS" ] || CONFIGURED_WORKERS="Not Set"
  LANGFLOW_POD="$(kubectl get pods -l app=langflow -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null | awk '{print $1}')"

  if [ -z "$LANGFLOW_POD" ]; then
    echo "Langflow pod not found."
    RUNNING_PROCESSES=0
  else
    # === Grep for gunicorn workers ===
    # The '[g]unicorn' is a trick to prevent grep from finding itself
    COMMAND_TO_RUN="ps -ef | grep 'uvicorn.workers.UvicornWorker' | grep -v 'grep' | wc -l"
    RUNNING_PROCESSES="$(kubectl exec "$LANGFLOW_POD" -- sh -lc "$COMMAND_TO_RUN" 2>/dev/null | tr -d '[:space:]' || echo 0)"
  fi

  case "$RUNNING_PROCESSES" in
    '' ) RUNNING_PROCESSES=0 ;;
  esac

  RUNNING_WORKERS=$RUNNING_PROCESSES

  echo "Configured workers (in ConfigMap): $CONFIGURED_WORKERS"
  echo "Running Gunicorn worker procs (in pod): $RUNNING_WORKERS"
  echo "Estimated worker processes:        $RUNNING_WORKERS"
}
# ========================================================================
# --- WORKER BENCHMARK ---
# ========================================================================

if [ -n "$FIXED_WORKER_COUNT" ]; then
  echo "--- Running benchmark with FIXED worker count: $FIXED_WORKER_COUNT ---"
  WORKER_COUNTS="$FIXED_WORKER_COUNT"
  # Disable premature stopping when testing a fixed count
  FAILURE_THRESHOLD=99999
else
  echo "--- Running benchmark with DYNAMIC worker scaling ---"
#  WORKER_COUNTS="1 2 4 8 16 32 64"
  WORKER_COUNTS="1 2 4 8 16"
fi

BEST_WORKERS=0
MAX_RPS=0.0

echo "Benchmark Job Started [Mode: workers]. Target Flow ID: $FLOW_ID. Test tool: $BENCHMARK_TYPE"

for workers in $WORKER_COUNTS; do
  echo "\n--- Testing with $workers workers ---"

  # === Patch WEB_CONCURRENCY ===
  echo "Patching ConfigMap to set WEB_CONCURRENCY=$workers..."
  kubectl patch configmap langflow-config --patch "{\"data\":{\"WEB_CONCURRENCY\":\"$workers\"}}"

  kubectl rollout restart deployment/langflow
  echo "Waiting for rollout to complete..."
#  kubectl rollout status deployment/langflow --timeout=180s
  echo "Waiting for pod to be ready..."
  kubectl wait --for=condition=ready pod -l app=langflow --timeout=180s

  echo "Giving Langflow extra time to initialize..."
  sleep 15

  check_workers
  echo "Running load test..."

  if [ "$BENCHMARK_TYPE" = "hey" ]; then
      echo "Running HEY benchmark..."
      JSON_PAYLOAD='{"input_value": "hello", "input_type": "text", "output_type": "text"}'
      CONC=$(( workers * 25 ))

      RESULT=$(hey -z 30s -c $CONC -t 30 \
        -H "x-api-key: $API_KEY" -H "Content-Type: application/json" \
        -m POST -d "$JSON_PAYLOAD" \
        "$LANGFLOW_SERVER_URL/api/v1/run/$FLOW_ID?stream=false")

      echo "--- Full 'hey' command output: ---"
      echo "$RESULT"
      echo "------------------------------------"

      RPS=$(echo "$RESULT" | awk '/Requests\/sec:/ {print $2}')

      echo "Result: $RPS Requests/sec"

      HTTP_ERRORS=$(echo "$RESULT" | awk '/\[5..\]/ {sum+=$2} END {print sum+0}')
      OTHER_ERRORS=$(echo "$RESULT" | awk '/Error distribution:/,0' | grep -o '\[[0-9]\+]' | tr -d '[]' | awk '{s+=$1} END {print s+0}')
      ERROR_COUNT=$((HTTP_ERRORS + OTHER_ERRORS))

  elif [ "$BENCHMARK_TYPE" = "locust" ]; then
      echo "Running LOCUST benchmark..."
      export FLOW_ID
      export API_KEY
      CSV_PREFIX="locust_results_${workers}"

      RESULT=$(locust -f /app/locustfile.py --headless \
        --users $(( workers * 50 )) --spawn-rate $(( workers * 25 )) \
        -t 30s --host "$LANGFLOW_SERVER_URL" \
        --csv="$CSV_PREFIX" --exit-code-on-error 1)

      STATS_CSV_FILE="${CSV_PREFIX}_stats.csv"
      if [ -f "$STATS_CSV_FILE" ]; then
        RPS=$(cat "$STATS_CSV_FILE" | grep "Aggregated" | awk -F',' '{print $10}'); RPS=${RPS:-0}
        REQUEST_COUNT=$(cat "$STATS_CSV_FILE" | grep "Aggregated" | awk -F',' '{print $3}'); REQUEST_COUNT=${REQUEST_COUNT:-0}
        FAILURE_COUNT=$(cat "$STATS_CSV_FILE" | grep "Aggregated" | awk -F',' '{print $4}'); FAILURE_COUNT=${FAILURE_COUNT:-0}
        if [ "$REQUEST_COUNT" -eq 0 ]; then echo "System unresponsive. 0 requests completed."; ERROR_COUNT=9999; else ERROR_COUNT=$FAILURE_COUNT; fi
        echo "\n--- Content of ${STATS_CSV_FILE} ---"
        cat "$STATS_CSV_FILE"
        echo "----------------------------------------\n"
      else
        echo "Warning: Locust stats CSV file not found: $STATS_CSV_FILE. Assuming 0 RPS and high error count."
        RPS=0.0
        ERROR_COUNT=999
      fi
  else
      echo "Error: Unknown benchmark type '$BENCHMARK_TYPE'. Use 'hey', 'locust' or 'threads'." >&2
      exit 1
  fi

  if [ -z "$ERROR_COUNT" ]; then
    ERROR_COUNT=0
  fi

  echo "Result with $workers workers: $RPS Requests/sec, Errors: $ERROR_COUNT"

  if [ $(echo "$RPS > $MAX_RPS" | bc -l) -eq 1 ] && [ $(echo "$ERROR_COUNT < $FAILURE_THRESHOLD" | bc) -eq 1 ]; then
    MAX_RPS=$RPS
    BEST_WORKERS=$workers
    echo ">>> New best worker count found! <<<"
  fi

  if [ "$ERROR_COUNT" -gt "$FAILURE_THRESHOLD" ]; then
    echo "\n--- System overloaded at $workers workers (Errors: $ERROR_COUNT) ---"
    echo "Stopping benchmark prematurely."
    break
  fi
done

echo "\n--- Worker Benchmark Finished ---"

if [ -z "$FIXED_WORKER_COUNT" ]; then
  echo "Optimal worker count: $BEST_WORKERS ($MAX_RPS Requests/sec)"
  # === Patch WEB_CONCURRENCY at the end ===
  echo "Patching ConfigMap with final optimal worker count: $BEST_WORKERS"
  kubectl patch configmap langflow-config --patch "{\"data\":{\"WEB_CONCURRENCY\":\"$BEST_WORKERS\"}}"
  echo -n "$BEST_WORKERS" > .optimal_workers
  echo "Benchmark complete. Result saved to .optimal_workers"
else
  echo "Fixed worker test complete."
  echo "Result: $RPS Requests/sec, Errors: $ERROR_COUNT"
fi
