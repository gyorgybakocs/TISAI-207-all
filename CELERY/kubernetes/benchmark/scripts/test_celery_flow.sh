#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║                    CELERY FLOW DEMONSTRATION TEST                      ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""

# === Configuration ===
LANGFLOW_URL="http://langflow:7860"
REDIS_POD=$(kubectl get pods -l app=redis -o jsonpath='{.items[0].metadata.name}')
REDIS_PASSWORD="redissecret"  # From redis-secret.yaml

# Get Flow ID and API Key from ConfigMap/Secret
FLOW_ID=$(kubectl get configmap langflow-config -o jsonpath='{.data.BENCHMARK_FLOW_ID}')
API_KEY=$(kubectl get secret langflow-secret -o jsonpath='{.data.BENCHMARK_API_KEY}' | base64 -d)

if [ -z "$FLOW_ID" ] || [ -z "$API_KEY" ]; then
    echo "❌ Error: FLOW_ID or API_KEY not found in Kubernetes!"
    echo "   Run 'make create-test-flow' first."
    exit 1
fi

echo "📋 Configuration:"
echo "   Flow ID: $FLOW_ID"
echo "   API Key: ${API_KEY:0:20}..."
echo "   Redis Pod: $REDIS_POD"
echo ""

# === STEP 1: Send API Request ===
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📤 STEP 1: Sending API request to Langflow..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

START_TIME=$(date +%s.%N)

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    "${LANGFLOW_URL}/api/v1/build/${FLOW_ID}/flow?event_delivery=polling" \
    -H "x-api-key: ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
      "inputs": {
        "input_value": "Hello from Celery test!"
      }
    }')

END_TIME=$(date +%s.%N)
ELAPSED=$(echo "$END_TIME - $START_TIME" | bc)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

echo ""
echo "✅ Response received in ${ELAPSED} seconds"
echo "   HTTP Status: $HTTP_CODE"
echo ""
echo "📄 Response Body:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

JOB_ID=$(echo "$BODY" | jq -r '.job_id // empty')

if [ -n "$JOB_ID" ]; then
  echo "🔁 Polling events for job_id: $JOB_ID"
  EVENTS=$(curl -s \
    "${LANGFLOW_URL}/api/v1/build/${JOB_ID}/events?event_delivery=polling" \
    -H "x-api-key: ${API_KEY}")
  echo "$EVENTS" | jq '.' 2>/dev/null || echo "$EVENTS"
else
  echo "⚠️  No job_id returned from build endpoint."
fi

# === STEP 2: Check Redis Broker (DB 0) ===
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 STEP 2: Checking Redis BROKER (DB 0) for pending tasks..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check for Celery task keys in broker
BROKER_KEYS=$(kubectl exec $REDIS_POD -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning -n 0 KEYS "celery-task-meta-*" 2>/dev/null || echo "")

if [ -z "$BROKER_KEYS" ]; then
    echo "⚠️  No 'celery-task-meta-*' keys found. Checking for other Celery keys..."
    ALL_KEYS=$(kubectl exec $REDIS_POD -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning -n 0 KEYS "*celery*" 2>/dev/null || echo "")

    if [ -z "$ALL_KEYS" ]; then
        echo "❌ No Celery-related keys found in Redis DB 0"
        echo "   This might mean:"
        echo "   - Celery is not properly configured"
        echo "   - Task was processed too quickly"
        echo "   - Tasks are stored with different key pattern"
    else
        echo "📦 Found Celery keys in broker:"
        echo "$ALL_KEYS"
        echo ""
        echo "🔎 Inspecting first key:"
        FIRST_KEY=$(echo "$ALL_KEYS" | head -n1)
        kubectl exec $REDIS_POD -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning -n 0 GET "$FIRST_KEY"
    fi
else
    echo "📦 Found task keys in broker:"
    echo "$BROKER_KEYS"
    echo ""
    echo "🔎 Inspecting first task:"
    FIRST_KEY=$(echo "$BROKER_KEYS" | head -n1)
    kubectl exec $REDIS_POD -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning -n 0 GET "$FIRST_KEY"
fi

echo ""
echo "⏱️  Waiting 3 seconds for worker to process task..."
sleep 3
echo ""

# === STEP 3: Monitor Worker Processing ===
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "👷 STEP 3: Checking Celery Worker logs..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

WORKER_POD=$(kubectl get pods -l app=langflow-worker -o jsonpath='{.items[0].metadata.name}')

if [ -z "$WORKER_POD" ]; then
    echo "❌ No worker pod found!"
else
    echo "📋 Worker pod: $WORKER_POD"
    echo ""
    echo "📜 Last 20 lines of worker logs:"
    echo "─────────────────────────────────────────────────────────────────────"
    kubectl logs $WORKER_POD --tail=20 | grep -E "(Task|Received|Succeeded|Failed)" || echo "No task-related logs found"
    echo "─────────────────────────────────────────────────────────────────────"
fi

echo ""

# === STEP 4: Check Redis Result Backend (DB 1) ===
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ STEP 4: Checking Redis RESULT BACKEND (DB 1) for completed tasks..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESULT_KEYS=$(kubectl exec $REDIS_POD -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning -n 1 KEYS "celery-task-meta-*" 2>/dev/null || echo "")

if [ -z "$RESULT_KEYS" ]; then
    echo "⚠️  No 'celery-task-meta-*' keys found in results. Checking for other patterns..."
    ALL_RESULT_KEYS=$(kubectl exec $REDIS_POD -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning -n 1 KEYS "*" 2>/dev/null || echo "")

    if [ -z "$ALL_RESULT_KEYS" ]; then
        echo "❌ No keys found in Redis DB 1 (result backend is empty)"
    else
        echo "📦 Found keys in result backend:"
        echo "$ALL_RESULT_KEYS"
        echo ""
        echo "🔎 Inspecting first result:"
        FIRST_RESULT_KEY=$(echo "$ALL_RESULT_KEYS" | head -n1)
        RESULT_VALUE=$(kubectl exec $REDIS_POD -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning -n 1 GET "$FIRST_RESULT_KEY")
        echo "$RESULT_VALUE" | jq '.' 2>/dev/null || echo "$RESULT_VALUE"
    fi
else
    echo "📦 Found result keys:"
    echo "$RESULT_KEYS"
    echo ""
    echo "🔎 Inspecting first result:"
    FIRST_RESULT_KEY=$(echo "$RESULT_KEYS" | head -n1)
    RESULT_VALUE=$(kubectl exec $REDIS_POD -- redis-cli -a "$REDIS_PASSWORD" --no-auth-warning -n 1 GET "$FIRST_RESULT_KEY")
    echo ""
    echo "📄 Result content:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$RESULT_VALUE" | jq '.' 2>/dev/null || echo "$RESULT_VALUE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║                          TEST COMPLETED                                ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "📊 Summary:"
echo "   • API Response Time: ${ELAPSED}s"
echo "   • Worker Pod: ${WORKER_POD:-N/A}"
echo "   • Redis Broker Keys: $(echo "$BROKER_KEYS" | wc -l)"
echo "   • Redis Result Keys: $(echo "$RESULT_KEYS" | wc -l)"
echo ""
