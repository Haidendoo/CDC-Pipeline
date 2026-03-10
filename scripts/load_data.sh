#!/bin/bash
set -e

echo "Loading job market data into PostgreSQL..."

# Copy CSV file into container
docker cp /home/den/DE/CDC-Pipeline/data/job_market_dataset.csv my_postgres_container:/tmp/job_market_dataset.csv

# Run SQL script to create table and load data
docker exec -i my_postgres_container psql -U myuser -d mydatabase < /home/den/DE/CDC-Pipeline/scripts/load_data.sql

echo "Data loaded successfully!"
echo ""
echo "To verify, run:"
echo "docker exec my_postgres_container psql -U myuser -d mydatabase -c 'SELECT COUNT(*) FROM job_market;'"
