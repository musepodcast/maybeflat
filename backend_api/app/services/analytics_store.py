from __future__ import annotations

import hmac
import os
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

from fastapi import HTTPException, Request
from psycopg.rows import dict_row
from psycopg.types.json import Json
from psycopg_pool import ConnectionPool


SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS visitors (
    visitor_id TEXT PRIMARY KEY,
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    first_ip TEXT,
    last_ip TEXT,
    user_agent TEXT
);

CREATE TABLE IF NOT EXISTS sessions (
    session_id TEXT PRIMARY KEY,
    visitor_id TEXT NOT NULL REFERENCES visitors(visitor_id) ON DELETE CASCADE,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    landing_path TEXT,
    referrer TEXT,
    country TEXT,
    entry_ip TEXT,
    last_ip TEXT,
    request_count INTEGER NOT NULL DEFAULT 0,
    event_count INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS events (
    id BIGSERIAL PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
    visitor_id TEXT NOT NULL REFERENCES visitors(visitor_id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    path TEXT,
    properties_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    ip TEXT,
    country TEXT,
    user_agent TEXT
);

CREATE TABLE IF NOT EXISTS request_logs (
    id BIGSERIAL PRIMARY KEY,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip TEXT,
    method TEXT NOT NULL,
    path TEXT NOT NULL,
    status_code INTEGER NOT NULL,
    duration_ms INTEGER NOT NULL,
    user_agent TEXT,
    referrer TEXT,
    request_id TEXT NOT NULL,
    country TEXT,
    visitor_id TEXT,
    session_id TEXT
);

CREATE INDEX IF NOT EXISTS idx_visitors_last_seen_at ON visitors (last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_last_seen_at ON sessions (last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_visitor_id ON sessions (visitor_id);
CREATE INDEX IF NOT EXISTS idx_events_occurred_at ON events (occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_events_name ON events (name);
CREATE INDEX IF NOT EXISTS idx_request_logs_occurred_at ON request_logs (occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_request_logs_ip ON request_logs (ip);
CREATE INDEX IF NOT EXISTS idx_request_logs_status_code ON request_logs (status_code);
"""

SUMMARY_QUERY = """
WITH suspicious AS (
    SELECT ip
    FROM request_logs
    WHERE occurred_at >= NOW() - MAKE_INTERVAL(hours => 1)
      AND ip IS NOT NULL
    GROUP BY ip
    HAVING COUNT(*) >= 50
        OR COUNT(*) FILTER (WHERE status_code >= 400) >= 20
        OR COUNT(DISTINCT path) >= 20
)
SELECT
    COALESCE((
        SELECT COUNT(DISTINCT visitor_id)::INT
        FROM sessions
        WHERE last_seen_at >= NOW() - MAKE_INTERVAL(hours => 24)
    ), 0) AS unique_visitors_24h,
    COALESCE((
        SELECT COUNT(*)::INT
        FROM sessions
        WHERE last_seen_at >= NOW() - MAKE_INTERVAL(hours => 24)
    ), 0) AS sessions_24h,
    COALESCE((
        SELECT COUNT(*)::INT
        FROM events
        WHERE occurred_at >= NOW() - MAKE_INTERVAL(hours => 24)
    ), 0) AS events_24h,
    COALESCE((
        SELECT COUNT(*)::INT
        FROM request_logs
        WHERE occurred_at >= NOW() - MAKE_INTERVAL(hours => 24)
    ), 0) AS requests_24h,
    COALESCE((
        SELECT COUNT(*)::INT
        FROM request_logs
        WHERE occurred_at >= NOW() - MAKE_INTERVAL(hours => 24)
          AND status_code >= 400
    ), 0) AS error_requests_24h,
    COALESCE((SELECT COUNT(*)::INT FROM suspicious), 0) AS suspicious_ip_count;
"""

TRAFFIC_BY_DAY_QUERY = """
WITH days AS (
    SELECT GENERATE_SERIES(
        DATE_TRUNC('day', NOW() - MAKE_INTERVAL(days => %s - 1)),
        DATE_TRUNC('day', NOW()),
        INTERVAL '1 day'
    ) AS day_bucket
),
session_counts AS (
    SELECT DATE_TRUNC('day', started_at) AS day_bucket, COUNT(*)::INT AS sessions
    FROM sessions
    WHERE started_at >= NOW() - MAKE_INTERVAL(days => %s)
    GROUP BY 1
),
event_counts AS (
    SELECT DATE_TRUNC('day', occurred_at) AS day_bucket, COUNT(*)::INT AS events
    FROM events
    WHERE occurred_at >= NOW() - MAKE_INTERVAL(days => %s)
    GROUP BY 1
),
request_counts AS (
    SELECT DATE_TRUNC('day', occurred_at) AS day_bucket, COUNT(*)::INT AS requests
    FROM request_logs
    WHERE occurred_at >= NOW() - MAKE_INTERVAL(days => %s)
    GROUP BY 1
)
SELECT
    TO_CHAR(days.day_bucket, 'YYYY-MM-DD') AS day,
    COALESCE(session_counts.sessions, 0) AS sessions,
    COALESCE(event_counts.events, 0) AS events,
    COALESCE(request_counts.requests, 0) AS requests
FROM days
LEFT JOIN session_counts ON session_counts.day_bucket = days.day_bucket
LEFT JOIN event_counts ON event_counts.day_bucket = days.day_bucket
LEFT JOIN request_counts ON request_counts.day_bucket = days.day_bucket
ORDER BY days.day_bucket DESC;
"""

SUSPICIOUS_IPS_QUERY = """
SELECT
    ip,
    COUNT(*)::INT AS request_count,
    COUNT(*) FILTER (WHERE status_code >= 400)::INT AS error_count,
    COUNT(DISTINCT path)::INT AS unique_paths,
    COUNT(DISTINCT session_id)::INT AS unique_sessions,
    MIN(occurred_at) AS first_seen_at,
    MAX(occurred_at) AS last_seen_at,
    CASE
        WHEN COUNT(*) >= 250 OR COUNT(*) FILTER (WHERE status_code >= 400) >= 80 THEN 'high'
        WHEN COUNT(*) >= 120 OR COUNT(*) FILTER (WHERE status_code >= 400) >= 40 THEN 'medium'
        ELSE 'low'
    END AS severity
FROM request_logs
WHERE occurred_at >= NOW() - MAKE_INTERVAL(mins => %s)
  AND ip IS NOT NULL
GROUP BY ip
HAVING COUNT(*) >= 50
    OR COUNT(*) FILTER (WHERE status_code >= 400) >= 20
    OR COUNT(DISTINCT path) >= 20
ORDER BY request_count DESC, last_seen_at DESC
LIMIT 25;
"""

_connection_pool: ConnectionPool | None = None
_request_log_enabled = False


def analytics_enabled() -> bool:
    return _connection_pool is not None


def request_log_enabled() -> bool:
    return _request_log_enabled and analytics_enabled()


def get_admin_token() -> str:
    return os.getenv("MAYBEFLAT_ADMIN_TOKEN", "").strip()


def require_admin_token(request: Request) -> None:
    expected = get_admin_token()
    if not expected:
        raise HTTPException(
            status_code=503,
            detail="Admin analytics are not configured. Set MAYBEFLAT_ADMIN_TOKEN.",
        )

    authorization = request.headers.get("authorization", "").strip()
    provided = ""
    if authorization.lower().startswith("bearer "):
        provided = authorization[7:].strip()
    if not provided:
        provided = request.headers.get("x-admin-token", "").strip()

    if not provided or not hmac.compare_digest(provided, expected):
        raise HTTPException(status_code=401, detail="Invalid admin token.")


def initialize_analytics_storage() -> bool:
    global _connection_pool, _request_log_enabled

    database_url = os.getenv("MAYBEFLAT_DATABASE_URL", "").strip()
    _request_log_enabled = os.getenv(
        "MAYBEFLAT_ENABLE_REQUEST_LOGGING",
        "1",
    ).strip().lower() not in {"0", "false", "no"}
    if not database_url:
        print("Analytics storage disabled. MAYBEFLAT_DATABASE_URL is not set.")
        return False

    if _connection_pool is not None:
        return True

    max_pool_size = max(
        2,
        int(os.getenv("MAYBEFLAT_DB_POOL_MAX_SIZE", "8")),
    )
    _connection_pool = ConnectionPool(
        conninfo=database_url,
        min_size=1,
        max_size=max_pool_size,
        kwargs={
            "autocommit": True,
            "row_factory": dict_row,
        },
        open=False,
    )
    _connection_pool.open()
    _connection_pool.wait()
    with _connection_pool.connection() as connection:
        for statement in SCHEMA_SQL.split(";"):
            normalized = statement.strip()
            if normalized:
                connection.execute(normalized)

    print("Analytics storage initialized.")
    return True


def close_analytics_storage() -> None:
    global _connection_pool
    if _connection_pool is None:
        return

    _connection_pool.close()
    _connection_pool = None


def extract_request_context(request: Request) -> dict[str, str | None]:
    forwarded_for = request.headers.get("cf-connecting-ip") or request.headers.get(
        "x-forwarded-for",
        "",
    )
    ip = forwarded_for.split(",")[0].strip() if forwarded_for else None
    if not ip and request.client is not None:
        ip = request.client.host

    country = request.headers.get("cf-ipcountry", "").strip() or None
    referrer = request.headers.get("referer", "").strip() or None
    user_agent = request.headers.get("user-agent", "").strip() or None
    visitor_id = request.headers.get("x-maybeflat-visitor-id", "").strip() or None
    session_id = request.headers.get("x-maybeflat-session-id", "").strip() or None

    return {
        "ip": ip,
        "country": country,
        "referrer": referrer,
        "user_agent": user_agent,
        "visitor_id": visitor_id,
        "session_id": session_id,
    }


def build_request_id(request: Request) -> str:
    existing = (
        request.headers.get("cf-ray", "").strip()
        or request.headers.get("x-request-id", "").strip()
    )
    if existing:
        return existing
    return uuid4().hex


def track_request(
    request: Request,
    *,
    status_code: int,
    duration_ms: int,
    request_id: str,
) -> None:
    if not request_log_enabled():
        return

    context = extract_request_context(request)
    path = request.url.path
    with _connection_pool.connection() as connection:
        with connection.transaction():
            _upsert_identity_records(
                connection,
                visitor_id=context["visitor_id"],
                session_id=context["session_id"],
                ip=context["ip"],
                country=context["country"],
                referrer=context["referrer"],
                user_agent=context["user_agent"],
                landing_path=path,
                increment_request_count=True,
                increment_event_count=False,
            )
            connection.execute(
                """
                INSERT INTO request_logs (
                    ip,
                    method,
                    path,
                    status_code,
                    duration_ms,
                    user_agent,
                    referrer,
                    request_id,
                    country,
                    visitor_id,
                    session_id
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    context["ip"],
                    request.method,
                    path,
                    status_code,
                    duration_ms,
                    context["user_agent"],
                    context["referrer"],
                    request_id,
                    context["country"],
                    context["visitor_id"],
                    context["session_id"],
                ),
            )


def record_product_event(
    request: Request,
    *,
    visitor_id: str,
    session_id: str,
    name: str,
    path: str | None,
    referrer: str | None,
    properties: dict[str, Any],
) -> None:
    if not analytics_enabled():
        return

    context = extract_request_context(request)
    with _connection_pool.connection() as connection:
        with connection.transaction():
            _upsert_identity_records(
                connection,
                visitor_id=visitor_id,
                session_id=session_id,
                ip=context["ip"],
                country=context["country"],
                referrer=referrer or context["referrer"],
                user_agent=context["user_agent"],
                landing_path=path,
                increment_request_count=False,
                increment_event_count=True,
            )
            connection.execute(
                """
                INSERT INTO events (
                    session_id,
                    visitor_id,
                    name,
                    path,
                    properties_json,
                    ip,
                    country,
                    user_agent
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    session_id,
                    visitor_id,
                    name,
                    path,
                    Json(properties),
                    context["ip"],
                    context["country"],
                    context["user_agent"],
                ),
            )


def fetch_admin_overview(
    *,
    window_days: int,
    suspicious_window_minutes: int,
) -> dict[str, Any]:
    if not analytics_enabled():
        raise HTTPException(
            status_code=503,
            detail="Analytics storage is unavailable.",
        )

    with _connection_pool.connection() as connection:
        summary = connection.execute(SUMMARY_QUERY).fetchone() or {}
        feature_usage = connection.execute(
            """
            SELECT name AS label, COUNT(*)::INT AS count
            FROM events
            WHERE occurred_at >= NOW() - MAKE_INTERVAL(days => %s)
            GROUP BY name
            ORDER BY count DESC, label ASC
            LIMIT 12
            """,
            (window_days,),
        ).fetchall()
        top_referrers = connection.execute(
            """
            SELECT
                COALESCE(NULLIF(referrer, ''), 'Direct / unknown') AS label,
                COUNT(*)::INT AS count
            FROM sessions
            WHERE last_seen_at >= NOW() - MAKE_INTERVAL(days => %s)
            GROUP BY label
            ORDER BY count DESC, label ASC
            LIMIT 10
            """,
            (window_days,),
        ).fetchall()
        top_landing_paths = connection.execute(
            """
            SELECT
                COALESCE(NULLIF(landing_path, ''), '/') AS label,
                COUNT(*)::INT AS count
            FROM sessions
            WHERE last_seen_at >= NOW() - MAKE_INTERVAL(days => %s)
            GROUP BY label
            ORDER BY count DESC, label ASC
            LIMIT 10
            """,
            (window_days,),
        ).fetchall()
        traffic_by_day = connection.execute(
            TRAFFIC_BY_DAY_QUERY,
            (window_days, window_days, window_days, window_days),
        ).fetchall()
        status_codes = connection.execute(
            """
            SELECT status_code, COUNT(*)::INT AS count
            FROM request_logs
            WHERE occurred_at >= NOW() - MAKE_INTERVAL(hours => 24)
            GROUP BY status_code
            ORDER BY count DESC, status_code ASC
            """,
        ).fetchall()
        suspicious_ips = connection.execute(
            SUSPICIOUS_IPS_QUERY,
            (suspicious_window_minutes,),
        ).fetchall()
        recent_requests = connection.execute(
            """
            SELECT
                occurred_at,
                ip,
                method,
                path,
                status_code,
                duration_ms,
                country,
                visitor_id,
                session_id,
                user_agent,
                referrer,
                request_id
            FROM request_logs
            ORDER BY occurred_at DESC
            LIMIT 120
            """,
        ).fetchall()
        recent_sessions = connection.execute(
            """
            SELECT
                session_id,
                visitor_id,
                started_at,
                last_seen_at,
                landing_path,
                referrer,
                country,
                entry_ip,
                last_ip,
                request_count,
                event_count
            FROM sessions
            ORDER BY last_seen_at DESC
            LIMIT 60
            """,
        ).fetchall()

    return {
        "generated_at": datetime.now(timezone.utc),
        "summary": summary,
        "feature_usage": feature_usage,
        "top_referrers": top_referrers,
        "top_landing_paths": top_landing_paths,
        "traffic_by_day": traffic_by_day,
        "status_codes": status_codes,
        "suspicious_ips": suspicious_ips,
        "recent_requests": recent_requests,
        "recent_sessions": recent_sessions,
    }


def _upsert_identity_records(
    connection,
    *,
    visitor_id: str | None,
    session_id: str | None,
    ip: str | None,
    country: str | None,
    referrer: str | None,
    user_agent: str | None,
    landing_path: str | None,
    increment_request_count: bool,
    increment_event_count: bool,
) -> None:
    if visitor_id:
        connection.execute(
            """
            INSERT INTO visitors (
                visitor_id,
                first_ip,
                last_ip,
                user_agent
            )
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (visitor_id) DO UPDATE
            SET
                last_seen_at = NOW(),
                last_ip = EXCLUDED.last_ip,
                user_agent = COALESCE(EXCLUDED.user_agent, visitors.user_agent)
            """,
            (visitor_id, ip, ip, user_agent),
        )

    if visitor_id and session_id:
        connection.execute(
            """
            INSERT INTO sessions (
                session_id,
                visitor_id,
                landing_path,
                referrer,
                country,
                entry_ip,
                last_ip,
                request_count,
                event_count,
                ended_at
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, NOW())
            ON CONFLICT (session_id) DO UPDATE
            SET
                last_seen_at = NOW(),
                ended_at = NOW(),
                last_ip = EXCLUDED.last_ip,
                country = COALESCE(EXCLUDED.country, sessions.country),
                referrer = COALESCE(sessions.referrer, EXCLUDED.referrer),
                landing_path = COALESCE(sessions.landing_path, EXCLUDED.landing_path),
                request_count = sessions.request_count + %s,
                event_count = sessions.event_count + %s
            """,
            (
                session_id,
                visitor_id,
                landing_path,
                referrer,
                country,
                ip,
                ip,
                1 if increment_request_count else 0,
                1 if increment_event_count else 0,
                1 if increment_request_count else 0,
                1 if increment_event_count else 0,
            ),
        )
