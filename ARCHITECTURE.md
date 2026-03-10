# CDC Pipeline Architecture

## System Overview

The CDC-Pipeline is a real-time data integration system that captures changes from a PostgreSQL source database, streams them through a message broker, and loads them into ClickHouse for analytics. The system uses dbt to transform raw change events into clean, documented data models.

## Core Components

### 1. PostgreSQL (Data Source)
- **Role**: Source database that generates change events
- **Technology**: PostgreSQL 16 with logical replication enabled
- **Port**: 5432
- **Configuration**: WAL level set to 'logical' to support CDC
- **Data Model**: Contains user-defined tables that will be replicated
- **Output**: Write-Ahead Logs (WAL) containing database changes

### 2. Debezium Server (Change Data Capture Engine)
- **Role**: Captures database changes from PostgreSQL logs
- **Technology**: Debezium 3.0.0
- **Function**: 
  - Monitors PostgreSQL WAL for INSERT, UPDATE, and DELETE operations
  - Converts database changes into structured JSON events
  - Extracts before/after snapshots of affected rows
  - Adds metadata (operation type, timestamp, source table)
- **Input**: PostgreSQL WAL logs
- **Output**: JSON-formatted change events

### 3. RabbitMQ (Message Broker)
- **Role**: Decouples CDC source from data warehouse sink
- **Technology**: RabbitMQ 3-management
- **Ports**: 
  - 5672 (AMQP protocol for message streaming)
  - 15672 (Management UI for monitoring queues)
- **Function**:
  - Receives change events from Debezium
  - Provides durable message queue storage
  - Enables multiple consumers to read the same events
  - Ensures no data loss between components
- **Queue Pattern**: Topic-based routing of CDC events by source table

### 4. ClickHouse (Analytics Warehouse)
- **Role**: Central data warehouse for storing raw CDC events and transformed data
- **Technology**: ClickHouse (all-in-one stack)
- **Ports**:
  - 8123 (HTTP API for queries and data loading)
  - 8080 (Web UI for interactive queries)
  - 4317/4318 (OTLP for observability)
- **Schemas**:
  - `default` - Contains raw event tables and dbt-transformed models
- **Users**: `api` account for automated data loading and queries
- **Storage**: Persistent `/var/lib/clickhouse` volume for data durability

### 5. dbt (Transformation & Documentation)
- **Role**: Transforms raw CDC events into clean, tested data models
- **Technology**: dbt-core with dbt-clickhouse adapter
- **Execution**: Automatically runs on container startup
- **Functions**:
  - Builds data models from SQL templates
  - Runs data quality tests on models
  - Generates interactive documentation with lineage
  - Serves web UI with model metadata
- **Port**: 8080 (internally), mapped to 8081 (localhost)
- **Startup Sequence**:
  1. `dbt deps` - Install dependencies
  2. `dbt debug` - Verify ClickHouse connection
  3. `dbt build` - Run models and tests
  4. `dbt docs generate` - Create documentation
  5. `dbt docs serve` - Start interactive UI

## Data Flow Architecture

### Step 1: Change Detection (PostgreSQL → Debezium)
When data is modified in PostgreSQL (INSERT, UPDATE, or DELETE), the change is written to the WAL. Debezium continuously monitors the WAL and detects these changes, extracting the full before/after state of the modified row.

### Step 2: Event Transformation (Debezium → JSON Events)
Debezium converts each detected change into a structured JSON event containing:
- `before`: Previous row state
- `after`: New row state
- `op`: Operation type (c=create, u=update, d=delete)
- `ts_ms`: Change timestamp
- `table`: Source table name
- `schema`: Source schema name
- `database`: Source database name

### Step 3: Event Publishing (Debezium → RabbitMQ)
Debezium publishes JSON events to RabbitMQ as messages. Each source table gets its own topic/routing key for organized message organization. Messages persist in RabbitMQ until consumed or expired.

### Step 4: Event Consumption (RabbitMQ → ClickHouse)
Consumer applications (or data connectors) read events from RabbitMQ and load them into ClickHouse raw event tables. The system stores each change event as a row, creating an immutable audit log of all database changes.

### Step 5: Data Transformation (ClickHouse → dbt Models)
dbt reads from the raw event tables in ClickHouse and creates transformed models through:
- **View Models**: Real-time transformed views of the latest state
- **Table Models**: Materialized tables for historical snapshots
- **Staging Models**: Intermediate transformations for data quality
- **Mart Models**: Final business-ready fact and dimension tables

### Step 6: Quality Assurance (dbt Tests)
dbt runs data quality tests on each model to ensure:
- No null values in critical columns
- Unique constraint enforcement
- Referential integrity
- Custom business logic validation

### Step 7: Documentation & Access (dbt → Web UI)
dbt generates an interactive web application that serves:
- Data lineage diagrams showing model dependencies
- Column descriptions and data types
- Test results and documentation
- Source-to-warehouse end-to-end lineage

## Event Schema Example

A typical CDC event for an UPDATE operation:

```json
{
  "before": {
    "id": 1,
    "name": "John Doe",
    "email": "john@example.com",
    "created_at": "2024-01-15T10:30:00Z"
  },
  "after": {
    "id": 1,
    "name": "John Doe",
    "email": "john.doe@company.com",
    "created_at": "2024-01-15T10:30:00Z"
  },
  "op": "u",
  "ts_ms": 1710153600000,
  "table": "users",
  "schema": "public",
  "database": "mydatabase"
}
```

## Container Orchestration

All components are containerized and orchestrated with Docker Compose:

- **my_postgres_container**: PostgreSQL 16 instance with CDC configuration
- **my_debezium_server**: Debezium CDC engine connected to PostgreSQL
- **my_rabbitmq_container**: RabbitMQ message broker with management UI
- **my_clickhouse_container**: ClickHouse OLAP database with health checks
- **my_dbt_container**: dbt transformation engine with docs server

Containers communicate through a shared Docker network named `cdc-pipeline_default`.

## Scalability & Resilience

### Decoupled Architecture
The message broker (RabbitMQ) decouples the CDC source from data warehouse, allowing:
- Independent scaling of each component
- Replay of events if warehouse is unavailable
- Multiple parallel consumers for the same event stream

### Logical Replication
PostgreSQL logical replication enables:
- Non-intrusive change capture (no application changes needed)
- Inclusion of DDL and DML events
- Slot management for reliable event delivery

### Data Persistence
- PostgreSQL volumes persist source data
- ClickHouse volumes persist warehouse data
- RabbitMQ persists messages to ensure no data loss
- dbt maintains manifest files for incremental parsing

## Monitoring & Observability

### Service Health Checks
- ClickHouse: HTTP ping endpoint at `GET /ping`
- PostgreSQL: `pg_isready` command availability
- RabbitMQ: Management API health endpoints

### Logging
- All containers output logs to Docker daemon
- View logs with `docker-compose logs [service-name]`
- Log aggregation can be added via Docker logging drivers

### Performance Monitoring
- ClickHouse provides query statistics and execution plans
- RabbitMQ management UI shows queue depths and message rates
- dbt execution logs show model build times and test results

## Security Considerations

### Authentication
- PostgreSQL: User/password-based (configured in docker-compose.yaml)
- ClickHouse: User/password-based with separate users for different access levels
- RabbitMQ: Default guest credentials (change in production)
- dbt: Uses ClickHouse user credentials for transformations

### Network Isolation
- All services communicate through a private Docker network
- Ports exposed to host are explicitly defined and limited
- No service-to-service communication uses public networks

## Extension Points

### Adding New Data Sources
1. Create new Debezium connector configuration
2. Point to different PostgreSQL database or table
3. Configure separate RabbitMQ topic/routing key
4. Load into new ClickHouse raw table
5. Add dbt models to transform new data

### Adding New Consumers
1. Create consumer application that reads from RabbitMQ
2. Route messages to alternative sinks (data lake, API, etc.)
3. Maintain event ordering and deduplication logic
4. Implement checkpointing for fault tolerance

### Adding Transformation Stages
1. Create new dbt models in `dbt/models/` directory
2. Reference existing raw or staging models as sources
3. Define tests in `dbt/models/schema.yml`
4. dbt automatically builds and documents new models
