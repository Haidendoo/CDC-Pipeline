{{ config(materialized='view') }}

WITH raw_messages AS (
    SELECT
        ingested_at,
        JSONExtractRaw(message, 'payload') AS payload_json
    FROM raw_job_market_cdc
),
parsed AS (
    SELECT
        ingested_at,
        JSONExtractString(payload_json, 'op') AS op,
        JSONExtractUInt(payload_json, 'ts_ms') AS ts_ms,
        fromUnixTimestamp64Milli(toInt64(JSONExtractUInt(payload_json, 'ts_ms'))) AS event_ts,

        nullIf(JSONExtractInt(payload_json, 'before', 'job_id'), 0) AS before_job_id,
        nullIf(JSONExtractInt(payload_json, 'after', 'job_id'), 0) AS after_job_id,
        JSONExtractString(payload_json, 'after', 'job_title') AS after_job_title,
        JSONExtractString(payload_json, 'after', 'company_size') AS after_company_size,
        JSONExtractString(payload_json, 'after', 'company_industry') AS after_company_industry,
        JSONExtractString(payload_json, 'after', 'country') AS after_country,
        JSONExtractString(payload_json, 'after', 'remote_type') AS after_remote_type,
        JSONExtractString(payload_json, 'after', 'experience_level') AS after_experience_level,
        JSONExtractInt(payload_json, 'after', 'years_experience') AS after_years_experience,
        JSONExtractString(payload_json, 'after', 'education_level') AS after_education_level,
        JSONExtractInt(payload_json, 'after', 'skills_python') AS after_skills_python,
        JSONExtractInt(payload_json, 'after', 'skills_sql') AS after_skills_sql,
        JSONExtractInt(payload_json, 'after', 'skills_ml') AS after_skills_ml,
        JSONExtractInt(payload_json, 'after', 'skills_deep_learning') AS after_skills_deep_learning,
        JSONExtractInt(payload_json, 'after', 'skills_cloud') AS after_skills_cloud,
        JSONExtractInt(payload_json, 'after', 'salary') AS after_salary,
        JSONExtractInt(payload_json, 'after', 'job_posting_month') AS after_job_posting_month,
        JSONExtractInt(payload_json, 'after', 'job_posting_year') AS after_job_posting_year,
        JSONExtractString(payload_json, 'after', 'hiring_urgency') AS after_hiring_urgency,
        JSONExtractInt(payload_json, 'after', 'job_openings') AS after_job_openings
    FROM raw_messages
)
SELECT *
FROM parsed