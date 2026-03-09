# CDC-Pipeline
This CDC pipeline uses Debezium to capture real-time database changes, streaming them as JSON events through RabbitMQ. These raw logs are then ingested into a warehouse where dbt transforms the "before/after" snapshots into clean, structured tables. This ensures low-latency data sync and a decoupled analytical architecture.
