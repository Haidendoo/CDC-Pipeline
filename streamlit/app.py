import os
import re
from typing import Dict, Tuple

import clickhouse_connect
import pandas as pd
import streamlit as st
from google import genai
from openai import OpenAI


st.set_page_config(page_title="CDC Control Room", page_icon="📡", layout="wide")


@st.cache_resource
def get_clickhouse_client():
    return clickhouse_connect.get_client(
        host=os.getenv("CH_HOST", "clickhouse"),
        port=int(os.getenv("CH_PORT", "8123")),
        username=os.getenv("CH_USER", "api"),
        password=os.getenv("CH_PASSWORD", "api"),
        database=os.getenv("CH_DATABASE", "default"),
    )


@st.cache_data(ttl=20)
def run_df(sql: str) -> pd.DataFrame:
    client = get_clickhouse_client()
    result = client.query_df(sql)
    return result


def sanitize_sql(candidate: str) -> Tuple[bool, str]:
    sql = candidate.strip()
    sql = re.sub(r"^```(?:sql)?", "", sql, flags=re.IGNORECASE).strip()
    sql = re.sub(r"```$", "", sql).strip()

    if ";" in sql:
        sql = sql.split(";", 1)[0].strip()

    lowered = sql.lower()
    blocked = [
        "insert ",
        "update ",
        "delete ",
        "drop ",
        "truncate ",
        "alter ",
        "create ",
        "grant ",
        "revoke ",
        "optimize ",
        "system ",
    ]

    if not (lowered.startswith("select") or lowered.startswith("with")):
        return False, "Only read-only SELECT queries are allowed."

    if any(keyword in lowered for keyword in blocked):
        return False, "Potentially unsafe SQL detected."

    if "limit" not in lowered:
        sql = f"{sql}\nLIMIT 200"

    return True, sql


@st.cache_data(ttl=30)
def get_snapshot_metrics() -> Dict[str, str]:
    metrics_sql = """
    SELECT
        (SELECT count() FROM raw_job_market_cdc) AS raw_rows,
        (SELECT count() FROM stg_job_market_cdc) AS stg_rows,
        (SELECT count() FROM fct_job_market_current) AS current_rows,
        (SELECT max(ingested_at) FROM raw_job_market_cdc) AS last_ingest,
        (SELECT max(event_ts) FROM stg_job_market_cdc) AS last_event_ts,
        dateDiff('second', (SELECT max(ingested_at) FROM raw_job_market_cdc), now()) AS ingest_lag_sec
    """
    row = run_df(metrics_sql).iloc[0].to_dict()
    for key in ["last_ingest", "last_event_ts"]:
        if pd.notna(row.get(key)):
            row[key] = str(row[key])
    return row


@st.cache_data(ttl=20)
def get_throughput() -> pd.DataFrame:
    return run_df(
        """
        SELECT
            toStartOfMinute(ingested_at) AS minute_bucket,
            count() AS events
        FROM raw_job_market_cdc
        WHERE ingested_at >= now() - INTERVAL 60 MINUTE
        GROUP BY minute_bucket
        ORDER BY minute_bucket
        """
    )


@st.cache_data(ttl=20)
def get_ops_mix() -> pd.DataFrame:
    return run_df(
        """
        SELECT
            op,
            count() AS events
        FROM stg_job_market_cdc
        WHERE event_ts >= now() - INTERVAL 60 MINUTE
        GROUP BY op
        ORDER BY events DESC
        """
    )


@st.cache_data(ttl=20)
def get_latest_current_rows() -> pd.DataFrame:
    return run_df(
        """
        SELECT *
        FROM fct_job_market_current
        ORDER BY last_event_ts DESC
        LIMIT 30
        """
    )


def render_monitoring_tab() -> None:
    st.subheader("Realtime CDC Monitoring")

    if st.button("Refresh metrics now"):
        st.cache_data.clear()

    metrics = get_snapshot_metrics()

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Raw CDC rows", f"{metrics['raw_rows']:,}")
    c2.metric("Staging rows", f"{metrics['stg_rows']:,}")
    c3.metric("Current-state rows", f"{metrics['current_rows']:,}")
    c4.metric("Ingest lag (sec)", f"{metrics['ingest_lag_sec']:,}")

    c5, c6 = st.columns(2)
    c5.caption(f"Last ingest time: {metrics['last_ingest']}")
    c6.caption(f"Last event time: {metrics['last_event_ts']}")

    throughput = get_throughput()
    ops_mix = get_ops_mix()

    left, right = st.columns(2)
    with left:
        st.markdown("### Events per minute (last 60m)")
        if {"minute_bucket", "events"}.issubset(throughput.columns):
            if throughput.empty:
                st.info("No events in the last 60 minutes.")
            else:
                st.line_chart(throughput, x="minute_bucket", y="events", use_container_width=True)
        else:
            st.info("Throughput data is not available yet.")
    with right:
        st.markdown("### Operation mix (last 60m)")
        if {"op", "events"}.issubset(ops_mix.columns):
            if ops_mix.empty:
                st.info("No operation events in the last 60 minutes.")
            else:
                st.bar_chart(ops_mix, x="op", y="events", use_container_width=True)
        else:
            st.info("Operation-mix data is not available yet.")

    st.markdown("### Latest current-state records")
    st.dataframe(get_latest_current_rows(), use_container_width=True, hide_index=True)


def ask_llm_for_sql(question: str) -> str:
    ollama_model = os.getenv("OLLAMA_MODEL", "").strip()
    ollama_base_url = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434/v1").strip()
    openai_api_key = os.getenv("OPENAI_API_KEY", "").strip()
    gemini_api_key = os.getenv("GEMINI_API_KEY", "").strip()
    openai_model = os.getenv("OPENAI_MODEL", "gpt-4.1-mini").strip()
    gemini_model = os.getenv("GEMINI_MODEL", "gemini-2.0-flash").strip()

    if not (ollama_model or openai_api_key or gemini_api_key):
        raise RuntimeError("Set OLLAMA_MODEL, OPENAI_API_KEY, or GEMINI_API_KEY to enable the AI Agent.")

    schema_context = """
You are a ClickHouse SQL assistant for a CDC analytics dataset.
Return ONLY one SQL query and nothing else.
Use read-only SQL only.

Available tables:
1) raw_job_market_cdc(message String, ingested_at DateTime)
2) stg_job_market_cdc(
   ingested_at DateTime,
   op String,
   ts_ms UInt64,
   event_ts DateTime64,
   before_job_id Int64,
   after_job_id Int64,
   after_job_title String,
   after_company_size String,
   after_company_industry String,
   after_country String,
   after_remote_type String,
   after_experience_level String,
   after_years_experience Int64,
   after_education_level String,
   after_skills_python Int64,
   after_skills_sql Int64,
   after_skills_ml Int64,
   after_skills_deep_learning Int64,
   after_skills_cloud Int64,
   after_salary Int64,
   after_job_posting_month Int64,
   after_job_posting_year Int64,
   after_hiring_urgency String,
   after_job_openings Int64
)
3) fct_job_market_current(
   job_id Int64,
   last_event_ts DateTime64,
   last_op String,
   job_title String,
   company_size String,
   company_industry String,
   country String,
   remote_type String,
   experience_level String,
   years_experience Int64,
   education_level String,
   skills_python Int64,
   skills_sql Int64,
   skills_ml Int64,
   skills_deep_learning Int64,
   skills_cloud Int64,
   salary Int64,
   job_posting_month Int64,
   job_posting_year Int64,
   hiring_urgency String,
   job_openings Int64
)

Rules:
- Use SELECT queries only.
- Prefer fct_job_market_current unless explicitly asked for raw/staging CDC detail.
- Add a LIMIT if user did not request full aggregation.
"""

    # Priority: Ollama (local) > OpenAI > Gemini
    if ollama_model:
        try:
            from httpx import Timeout
            client = OpenAI(
                api_key="ollama",
                base_url=ollama_base_url,
                timeout=Timeout(60.0),  # 60s for local CPU inference with 1B model
            )
            completion = client.chat.completions.create(
                model=ollama_model,
                messages=[
                    {"role": "system", "content": schema_context},
                    {"role": "user", "content": question},
                ],
                temperature=0,
            )
            content = completion.choices[0].message.content
            if not content:
                raise RuntimeError("Ollama returned an empty response.")
            return content.strip()
        except Exception as e:
            raise RuntimeError(
                f"Ollama inference failed. Verify Ollama is running at {ollama_base_url} "
                f"and model '{ollama_model}' is loaded. Error: {str(e)}"
            )

    if openai_api_key:
        client = OpenAI(api_key=openai_api_key)
        response = client.responses.create(
            model=openai_model,
            input=[
                {"role": "system", "content": schema_context},
                {"role": "user", "content": question},
            ],
        )
        return response.output_text.strip()

    # Fallback to Gemini
    gemini_client = genai.Client(api_key=gemini_api_key)
    prompt = (
        f"{schema_context}\n\n"
        f"User question:\n{question}\n\n"
        "Return only SQL."
    )
    response = gemini_client.models.generate_content(model=gemini_model, contents=prompt)
    content = (response.text or "").strip()
    if not content:
        raise RuntimeError("Gemini returned an empty response.")
    return content


def render_agent_tab() -> None:
    st.subheader("AI Analyst Agent")
    st.caption("Ask business or operational questions. The agent generates safe read-only ClickHouse SQL.")

    question = st.text_area(
        "Question",
        placeholder="Example: Top 10 countries by average salary for remote roles in the current dataset",
        height=100,
    )

    run = st.button("Ask agent")
    if not run:
        return

    if not question.strip():
        st.warning("Please enter a question.")
        return

    with st.spinner("Generating SQL..."):
        try:
            candidate_sql = ask_llm_for_sql(question)
            ok, safe_sql_or_error = sanitize_sql(candidate_sql)
            if not ok:
                st.error(safe_sql_or_error)
                st.code(candidate_sql, language="sql")
                return

            safe_sql = safe_sql_or_error
            st.markdown("### Generated SQL")
            st.code(safe_sql, language="sql")

            result = run_df(safe_sql)
            st.markdown("### Result")
            st.dataframe(result, use_container_width=True, hide_index=True)

        except Exception as exc:
            st.error(f"Agent execution failed: {exc}")


st.title("CDC Pipeline Control Room")
st.caption("Monitoring + AI query assistant for your realtime ClickHouse warehouse")

monitor_tab, agent_tab = st.tabs(["Monitoring", "AI Agent"])

with monitor_tab:
    render_monitoring_tab()

with agent_tab:
    render_agent_tab()
