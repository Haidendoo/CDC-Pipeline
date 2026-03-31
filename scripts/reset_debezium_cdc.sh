#!/bin/bash
# reset_debezium_cdc.sh
# Safely reset Debezium replication slot and publication after DB/table recreation

set -e

PG_CONTAINER=my_postgres_container
DB_NAME=mydatabase
DB_USER=myuser
DEBEZIUM_CONTAINER=my_debezium_server
SLOT_NAME=debezium
PUBLICATION_NAME=dbz_publication

# Stop Debezium to release the replication slot
echo "Stopping Debezium container..."
docker stop "$DEBEZIUM_CONTAINER"

# Drop replication slot
echo "Dropping replication slot..."
docker exec -i "$PG_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT pg_drop_replication_slot('$SLOT_NAME');" || echo "Slot may not exist, continuing."

# Drop and recreate publication
echo "Dropping and recreating publication..."
docker exec -i "$PG_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "DROP PUBLICATION IF EXISTS $PUBLICATION_NAME; CREATE PUBLICATION $PUBLICATION_NAME FOR ALL TABLES;"

# Start Debezium again
echo "Starting Debezium container..."
docker start "$DEBEZIUM_CONTAINER"

echo "Debezium CDC reset complete."
