#!/bin/bash

echo "--- Live Postgres connection monitor (langflow_db) ---"
PG_POD=$(kubectl get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}')

if [ -z "$PG_POD" ]; then
    echo "❌ Postgres pod not found."
    exit 1
fi

echo "Monitoring connections from pod: $PG_POD (Press Ctrl+C to stop)"

kubectl exec deploy/postgres -- bash -lc "psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -tA -c \"SELECT to_char(now(), 'HH24:MI:SS') || ' | active=' || count(*) FROM pg_stat_activity WHERE datname='langflow_db';\""