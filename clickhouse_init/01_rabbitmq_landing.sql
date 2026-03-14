CREATE TABLE IF NOT EXISTS default.raw_job_market_cdc
(
    ingested_at DateTime64(3) DEFAULT now64(3),
    message String
)
ENGINE = MergeTree
ORDER BY ingested_at;

DROP VIEW IF EXISTS default.mv_rabbitmq_job_market_to_raw;
DROP TABLE IF EXISTS default.rabbitmq_job_market_queue;

CREATE TABLE default.rabbitmq_job_market_queue
(
    message String
)
ENGINE = RabbitMQ
SETTINGS
    rabbitmq_host_port = 'rabbitmq:5672',
    rabbitmq_exchange_name = 'products',
    rabbitmq_exchange_type = 'direct',
    rabbitmq_routing_key_list = 'products,tutorial.public.job_market',
    rabbitmq_username = 'guest',
    rabbitmq_password = 'guest',
    rabbitmq_format = 'JSONAsString',
    rabbitmq_num_consumers = 1;

CREATE MATERIALIZED VIEW default.mv_rabbitmq_job_market_to_raw
TO default.raw_job_market_cdc
AS
SELECT
    now64(3) AS ingested_at,
    message
FROM default.rabbitmq_job_market_queue;