#!/bin/bash

echo "--- Live PgBouncer connection monitor (langflow_db) ---"
PSQL_POD=$(kubectl get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}')

if [ -z "$PSQL_POD" ]; then
    echo "❌ Postgres (psql client) pod not found."
    exit 1
fi

echo "Monitoring PgBouncer *from* pod: $PSQL_POD (Press Ctrl+C to stop)"
echo "--- (cl_active = Clients | sv_active = Servers) ---"


kubectl exec -it $PSQL_POD -- bash -lc "
    export PGPASSWORD='password';
    while true;
    do
        psql -U 'postgres_user' -d 'pgbouncer' -h 'pgbouncer' -p 6432 -tA -c 'SHOW STATS;' 2>/dev/null \
        | grep --line-buffered 'langflow_db' | awk -F'|' '{print \"[PGBOUNCER] cl_active=\" \$3 \" | cl_waiting=\" \$4 \" | sv_active=\" \$5 \" | sv_idle=\" \$7 \" | maxwait(ms)=\" \$10; fflush()}'
        sleep 2
    done
"