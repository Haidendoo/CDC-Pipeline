-- Create job market table
DROP TABLE IF EXISTS job_market CASCADE;

CREATE TABLE job_market (
    job_id INTEGER PRIMARY KEY,
    job_title VARCHAR(255),
    company_size VARCHAR(50),
    company_industry VARCHAR(100),
    country VARCHAR(100),
    remote_type VARCHAR(50),
    experience_level VARCHAR(50),
    years_experience INTEGER,
    education_level VARCHAR(50),
    skills_python SMALLINT,
    skills_sql SMALLINT,
    skills_ml SMALLINT,
    skills_deep_learning SMALLINT,
    skills_cloud SMALLINT,
    salary INTEGER,
    job_posting_month INTEGER,
    job_posting_year INTEGER,
    hiring_urgency VARCHAR(50),
    job_openings INTEGER,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Copy data from CSV
COPY job_market (
    job_id,
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
)
FROM '/tmp/job_market_dataset.csv'
DELIMITER ','
CSV HEADER;

-- Verify data loaded
SELECT COUNT(*) as total_rows FROM job_market;
SELECT * FROM job_market LIMIT 5;
