#!/bin/bash
set -euo pipefail

CLICKHOUSE_CONTAINER="${CLICKHOUSE_CONTAINER:-my_clickhouse_container}"
SQL_FILE="/home/den/DE/CDC-Pipeline/clickhouse_init/01_rabbitmq_landing.sql"

if ! docker ps --format '{{.Names}}' | grep -qx "$CLICKHOUSE_CONTAINER"; then
  echo "Container '$CLICKHOUSE_CONTAINER' is not running. Start the stack first with: docker compose up -d"
  exit 1
fi

if [[ ! -f "$SQL_FILE" ]]; then
  echo "Landing SQL file not found at $SQL_FILE"
  exit 1
fi

echo "Applying ClickHouse landing DDL from $SQL_FILE ..."
docker exec -i "$CLICKHOUSE_CONTAINER" clickhouse-client -n < "$SQL_FILE"
echo "ClickHouse landing objects are ready."