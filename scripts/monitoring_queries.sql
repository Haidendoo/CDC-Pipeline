-- CDC pipeline monitoring queries for ClickHouse

-- 1) End-to-end freshness and lag
SELECT
    (SELECT max(ingested_at) FROM default.raw_job_market_cdc) AS last_ingest,
    (SELECT max(event_ts) FROM default.stg_job_market_cdc) AS last_event_ts,
    dateDiff('second', (SELECT max(ingested_at) FROM default.raw_job_market_cdc), now()) AS ingest_lag_sec,
    dateDiff('second', (SELECT max(event_ts) FROM default.stg_job_market_cdc), now()) AS event_lag_sec;

-- 2) Row counts per layer
SELECT
    (SELECT count() FROM default.raw_job_market_cdc) AS raw_rows,
    (SELECT count() FROM default.stg_job_market_cdc) AS stg_rows,
    (SELECT count() FROM default.fct_job_market_current) AS current_rows;

-- 3) Throughput by minute (last 60 minutes)
SELECT
    toStartOfMinute(ingested_at) AS minute_bucket,
    count() AS events
FROM default.raw_job_market_cdc
WHERE ingested_at >= now() - INTERVAL 60 MINUTE
GROUP BY minute_bucket
ORDER BY minute_bucket;

-- 4) Operation mix by minute (last 60 minutes)
SELECT
    toStartOfMinute(event_ts) AS minute_bucket,
    op,
    count() AS events
FROM default.stg_job_market_cdc
WHERE event_ts >= now() - INTERVAL 60 MINUTE
GROUP BY minute_bucket, op
ORDER BY minute_bucket, op;

-- 5) Duplicate protection check in current-state table
SELECT
    job_id,
    count() AS versions
FROM default.fct_job_market_current
GROUP BY job_id
HAVING versions > 1
ORDER BY versions DESC
LIMIT 20;
