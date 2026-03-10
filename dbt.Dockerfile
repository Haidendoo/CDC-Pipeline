FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
	PYTHONUNBUFFERED=1 \
	PIP_NO_CACHE_DIR=1 \
	DBT_PROFILES_DIR=/usr/app/.dbt

WORKDIR /usr/app

# Install minimal system dependencies commonly needed by Python packages.
RUN apt-get update \
	&& apt-get install -y --no-install-recommends build-essential git \
	&& rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip \
	&& pip install dbt-core dbt-clickhouse

RUN mkdir -p /usr/app/.dbt

CMD ["dbt", "--version"]
