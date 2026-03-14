{{ config(materialized='view') }}

WITH ranked_events AS (
    SELECT
        coalesce(after_job_id, before_job_id) AS job_id,
        op,
        ts_ms,
        event_ts,
        ingested_at,
        after_job_title AS job_title,
        after_company_size AS company_size,
        after_company_industry AS company_industry,
        after_country AS country,
        after_remote_type AS remote_type,
        after_experience_level AS experience_level,
        after_years_experience AS years_experience,
        after_education_level AS education_level,
        after_skills_python AS skills_python,
        after_skills_sql AS skills_sql,
        after_skills_ml AS skills_ml,
        after_skills_deep_learning AS skills_deep_learning,
        after_skills_cloud AS skills_cloud,
        after_salary AS salary,
        after_job_posting_month AS job_posting_month,
        after_job_posting_year AS job_posting_year,
        after_hiring_urgency AS hiring_urgency,
        after_job_openings AS job_openings,
        row_number() OVER (
            PARTITION BY coalesce(after_job_id, before_job_id)
            ORDER BY ts_ms DESC, ingested_at DESC
        ) AS event_rank
    FROM {{ ref('stg_job_market_cdc') }}
    WHERE coalesce(after_job_id, before_job_id) IS NOT NULL
)
SELECT
    job_id,
    event_ts AS last_event_ts,
    op AS last_op,
    job_title,
    company_size,
    company_industry,
    country,
    remote_type,
    experience_level,
    years_experience,
    education_level,
    skills_python,
    skills_sql,
    skills_ml,
    skills_deep_learning,
    skills_cloud,
    salary,
    job_posting_month,
    job_posting_year,
    hiring_urgency,
    job_openings
FROM ranked_events
WHERE event_rank = 1
  AND op != 'd'