from __future__ import annotations

import csv
import hmac
import os
from datetime import datetime, timezone
from io import StringIO
from typing import Any
from uuid import uuid4

from fastapi import HTTPException, Request
from psycopg.rows import dict_row
from psycopg.types.json import Json
from psycopg_pool import ConnectionPool


SCHEMA_STATEMENTS = [
    """
    CREATE TABLE IF NOT EXISTS visitors (
        visitor_id TEXT PRIMARY KEY,
        first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        first_ip TEXT,
        last_ip TEXT,
        user_agent TEXT
    )
    """,
    """
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
    )
    """,
    """
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
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS request_logs (
        id BIGSERIAL PRIMARY KEY,
        occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        ip TEXT,
        method TEXT NOT NULL,
        path TEXT NOT NULL,
        route_group TEXT NOT NULL DEFAULT '/',
        status_code INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL,
        response_size_bytes INTEGER NOT NULL DEFAULT 0,
        user_agent TEXT,
        referrer TEXT,
        request_id TEXT NOT NULL,
        country TEXT,
        visitor_id TEXT,
        session_id TEXT
    )
    """,
    "ALTER TABLE request_logs ADD COLUMN IF NOT EXISTS route_group TEXT NOT NULL DEFAULT '/'",
    "ALTER TABLE request_logs ADD COLUMN IF NOT EXISTS response_size_bytes INTEGER NOT NULL DEFAULT 0",
    "CREATE INDEX IF NOT EXISTS idx_visitors_last_seen_at ON visitors (last_seen_at DESC)",
    "CREATE INDEX IF NOT EXISTS idx_sessions_last_seen_at ON sessions (last_seen_at DESC)",
    "CREATE INDEX IF NOT EXISTS idx_sessions_visitor_id ON sessions (visitor_id)",
    "CREATE INDEX IF NOT EXISTS idx_events_occurred_at ON events (occurred_at DESC)",
    "CREATE INDEX IF NOT EXISTS idx_events_name ON events (name)",
    "CREATE INDEX IF NOT EXISTS idx_request_logs_occurred_at ON request_logs (occurred_at DESC)",
    "CREATE INDEX IF NOT EXISTS idx_request_logs_ip ON request_logs (ip)",
    "CREATE INDEX IF NOT EXISTS idx_request_logs_status_code ON request_logs (status_code)",
    "CREATE INDEX IF NOT EXISTS idx_request_logs_route_group ON request_logs (route_group)",
    "CREATE INDEX IF NOT EXISTS idx_request_logs_session_id ON request_logs (session_id)",
]

WINDOW_TO_INTERVAL = {
    "1h": "1 hour",
    "24h": "24 hours",
    "7d": "7 days",
    "30d": "30 days",
}

WINDOW_TO_BUCKET = {
    "1h": ("minute", "YYYY-MM-DD HH24:MI", 61),
    "24h": ("hour", "YYYY-MM-DD HH24:00", 25),
    "7d": ("day", "YYYY-MM-DD", 8),
    "30d": ("day", "YYYY-MM-DD", 31),
}

DEVICE_CASE = """
CASE
    WHEN COALESCE(user_agent, '') = '' THEN 'Unknown'
    WHEN user_agent ILIKE '%%bot%%'
      OR user_agent ILIKE '%%crawler%%'
      OR user_agent ILIKE '%%spider%%'
      OR user_agent ILIKE '%%preview%%' THEN 'Bot'
    WHEN user_agent ILIKE '%%ipad%%'
      OR user_agent ILIKE '%%tablet%%' THEN 'Tablet'
    WHEN user_agent ILIKE '%%iphone%%'
      OR user_agent ILIKE '%%android%%'
      OR user_agent ILIKE '%%mobile%%' THEN 'Mobile'
    ELSE 'Desktop'
END
"""

BROWSER_CASE = """
CASE
    WHEN COALESCE(user_agent, '') = '' THEN 'Unknown'
    WHEN user_agent ILIKE '%%bot%%'
      OR user_agent ILIKE '%%crawler%%'
      OR user_agent ILIKE '%%spider%%' THEN 'Bot'
    WHEN user_agent ILIKE '%%edg/%%' THEN 'Edge'
    WHEN user_agent ILIKE '%%opr/%%' OR user_agent ILIKE '%%opera%%' THEN 'Opera'
    WHEN user_agent ILIKE '%%firefox/%%' THEN 'Firefox'
    WHEN user_agent ILIKE '%%chrome/%%' THEN 'Chrome'
    WHEN user_agent ILIKE '%%safari/%%' THEN 'Safari'
    ELSE 'Other'
END
"""

_connection_pool: ConnectionPool | None = None
_request_log_enabled = False


def analytics_enabled() -> bool:
    return _connection_pool is not None


def request_log_enabled() -> bool:
    return _request_log_enabled and analytics_enabled()


def get_admin_token() -> str:
    return os.getenv("MAYBEFLAT_ADMIN_TOKEN", "").strip()


def _env_flag(name: str, default: bool = False) -> bool:
    value = os.getenv(name, "").strip().lower()
    if not value:
        return default
    return value not in {"0", "false", "no", "off"}


def _split_env_list(name: str) -> set[str]:
    return {
        item.strip().lower()
        for item in os.getenv(name, "").split(",")
        if item.strip()
    }


def require_admin_access(request: Request) -> None:
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

    if not _env_flag("MAYBEFLAT_ADMIN_REQUIRE_CLOUDFLARE_ACCESS"):
        return

    cf_email = request.headers.get("cf-access-authenticated-user-email", "").strip()
    cf_jwt = request.headers.get("cf-access-jwt-assertion", "").strip()
    cf_client_id = request.headers.get("cf-access-client-id", "").strip()
    if not cf_email and not cf_jwt and not cf_client_id:
        raise HTTPException(
            status_code=403,
            detail="Cloudflare Access is required for /admin.",
        )

    allowed_emails = _split_env_list("MAYBEFLAT_ADMIN_ACCESS_ALLOWED_EMAILS")
    allowed_domains = _split_env_list("MAYBEFLAT_ADMIN_ACCESS_ALLOWED_DOMAINS")
    if not cf_email:
        if allowed_emails or allowed_domains:
            raise HTTPException(
                status_code=403,
                detail="Cloudflare Access email is required for this admin policy.",
            )
        return

    normalized_email = cf_email.lower()
    email_domain = normalized_email.split("@", 1)[1] if "@" in normalized_email else ""
    if allowed_emails and normalized_email not in allowed_emails:
        raise HTTPException(status_code=403, detail="Cloudflare Access email is not allowed.")
    if allowed_domains and email_domain not in allowed_domains:
        raise HTTPException(status_code=403, detail="Cloudflare Access domain is not allowed.")


def initialize_analytics_storage() -> bool:
    global _connection_pool, _request_log_enabled

    database_url = os.getenv("MAYBEFLAT_DATABASE_URL", "").strip()
    _request_log_enabled = _env_flag("MAYBEFLAT_ENABLE_REQUEST_LOGGING", default=True)
    if not database_url:
        print("Analytics storage disabled. MAYBEFLAT_DATABASE_URL is not set.")
        return False
    if _connection_pool is not None:
        return True

    _connection_pool = ConnectionPool(
        conninfo=database_url,
        min_size=1,
        max_size=max(2, int(os.getenv("MAYBEFLAT_DB_POOL_MAX_SIZE", "8"))),
        kwargs={"autocommit": True, "row_factory": dict_row},
        open=False,
    )
    _connection_pool.open()
    _connection_pool.wait()
    with _connection_pool.connection() as connection:
        for statement in SCHEMA_STATEMENTS:
            connection.execute(statement)

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

    return {
        "ip": ip,
        "country": request.headers.get("cf-ipcountry", "").strip() or None,
        "referrer": request.headers.get("referer", "").strip() or None,
        "user_agent": request.headers.get("user-agent", "").strip() or None,
        "visitor_id": request.headers.get("x-maybeflat-visitor-id", "").strip() or None,
        "session_id": request.headers.get("x-maybeflat-session-id", "").strip() or None,
    }


def build_request_id(request: Request) -> str:
    existing = request.headers.get("cf-ray", "").strip() or request.headers.get(
        "x-request-id",
        "",
    ).strip()
    return existing or uuid4().hex


def normalize_route_group(path: str) -> str:
    if not path:
        return "/"
    if path.startswith("/map/tiles/"):
        return "/map/tiles/:tile"
    if path.startswith("/admin/analytics/ip/"):
        return "/admin/analytics/ip/:ip"
    if path.startswith("/admin/analytics/sessions/"):
        return "/admin/analytics/sessions/:session"
    return path


def track_request(
    request: Request,
    *,
    status_code: int,
    duration_ms: int,
    request_id: str,
    response_size_bytes: int = 0,
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
                    route_group,
                    status_code,
                    duration_ms,
                    response_size_bytes,
                    user_agent,
                    referrer,
                    request_id,
                    country,
                    visitor_id,
                    session_id
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    context["ip"],
                    request.method,
                    path,
                    normalize_route_group(path),
                    status_code,
                    duration_ms,
                    max(0, int(response_size_bytes)),
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


def fetch_admin_overview(*, window: str, suspicious_window_minutes: int) -> dict[str, Any]:
    if not analytics_enabled():
        raise HTTPException(status_code=503, detail="Analytics storage is unavailable.")

    interval = _window_interval(window)
    bucket_unit, bucket_format, bucket_limit = WINDOW_TO_BUCKET[window]
    with _connection_pool.connection() as connection:
        summary = connection.execute(
            """
            WITH suspicious AS (
                SELECT ip
                FROM request_logs
                WHERE occurred_at >= NOW() - MAKE_INTERVAL(mins => %s)
                  AND ip IS NOT NULL
                GROUP BY ip
                HAVING COUNT(*) >= 50
                    OR COUNT(*) FILTER (WHERE status_code >= 400) >= 20
                    OR COUNT(*) FILTER (WHERE status_code = 404) >= 10
                    OR COUNT(*) FILTER (WHERE route_group LIKE '/admin%%') >= 8
                    OR COUNT(DISTINCT session_id) >= 12
            )
            SELECT
                COALESCE((SELECT COUNT(DISTINCT visitor_id)::INT FROM sessions WHERE last_seen_at >= NOW() - %s::interval), 0) AS unique_visitors,
                COALESCE((SELECT COUNT(*)::INT FROM sessions WHERE last_seen_at >= NOW() - %s::interval), 0) AS sessions,
                COALESCE((SELECT COUNT(*)::INT FROM events WHERE occurred_at >= NOW() - %s::interval), 0) AS events,
                COALESCE((SELECT COUNT(*)::INT FROM request_logs WHERE occurred_at >= NOW() - %s::interval), 0) AS requests,
                COALESCE((SELECT COUNT(*)::INT FROM request_logs WHERE occurred_at >= NOW() - %s::interval AND status_code >= 400), 0) AS error_requests,
                COALESCE((SELECT COUNT(*)::INT FROM suspicious), 0) AS suspicious_ip_count
            """,
            (
                suspicious_window_minutes,
                interval,
                interval,
                interval,
                interval,
                interval,
            ),
        ).fetchone() or {}
        latency = connection.execute(
            """
            SELECT
                COALESCE(AVG(duration_ms), 0)::FLOAT AS average_ms,
                COALESCE(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_ms), 0)::FLOAT AS p50_ms,
                COALESCE(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_ms), 0)::FLOAT AS p95_ms,
                COALESCE(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_ms), 0)::FLOAT AS p99_ms,
                COALESCE(AVG(response_size_bytes), 0)::INT AS average_response_size_bytes
            FROM request_logs
            WHERE occurred_at >= NOW() - %s::interval
            """,
            (interval,),
        ).fetchone() or {}
        feature_usage = connection.execute(
            """
            WITH grouped AS (
                SELECT
                    REGEXP_REPLACE(name, '(_failed|_succeeded)$', '') AS label,
                    COUNT(*)::INT AS count,
                    COUNT(*) FILTER (WHERE name LIKE '%%_succeeded')::INT AS success_count,
                    COUNT(*) FILTER (WHERE name LIKE '%%_failed')::INT AS failure_count
                FROM events
                WHERE occurred_at >= NOW() - %s::interval
                GROUP BY 1
            )
            SELECT label, count, success_count, failure_count
            FROM grouped
            ORDER BY count DESC, label ASC
            LIMIT 16
            """,
            (interval,),
        ).fetchall()
        top_referrers = _label_counts(
            connection,
            """
            SELECT COALESCE(NULLIF(referrer, ''), 'Direct / unknown') AS label, COUNT(*)::INT AS count
            FROM sessions
            WHERE last_seen_at >= NOW() - %s::interval
            GROUP BY 1
            ORDER BY count DESC, label ASC
            LIMIT 10
            """,
            interval,
        )
        top_landing_paths = _label_counts(
            connection,
            """
            SELECT COALESCE(NULLIF(landing_path, ''), '/') AS label, COUNT(*)::INT AS count
            FROM sessions
            WHERE last_seen_at >= NOW() - %s::interval
            GROUP BY 1
            ORDER BY count DESC, label ASC
            LIMIT 10
            """,
            interval,
        )
        traffic_buckets = connection.execute(
            f"""
            WITH buckets AS (
                SELECT GENERATE_SERIES(
                    DATE_TRUNC('{bucket_unit}', NOW() - %s::interval),
                    DATE_TRUNC('{bucket_unit}', NOW()),
                    INTERVAL '1 {bucket_unit}'
                ) AS bucket
            ),
            session_counts AS (
                SELECT DATE_TRUNC('{bucket_unit}', started_at) AS bucket, COUNT(*)::INT AS sessions
                FROM sessions
                WHERE started_at >= NOW() - %s::interval
                GROUP BY 1
            ),
            event_counts AS (
                SELECT DATE_TRUNC('{bucket_unit}', occurred_at) AS bucket, COUNT(*)::INT AS events
                FROM events
                WHERE occurred_at >= NOW() - %s::interval
                GROUP BY 1
            ),
            request_counts AS (
                SELECT DATE_TRUNC('{bucket_unit}', occurred_at) AS bucket, COUNT(*)::INT AS requests
                FROM request_logs
                WHERE occurred_at >= NOW() - %s::interval
                GROUP BY 1
            )
            SELECT
                TO_CHAR(buckets.bucket, '{bucket_format}') AS bucket,
                COALESCE(session_counts.sessions, 0) AS sessions,
                COALESCE(event_counts.events, 0) AS events,
                COALESCE(request_counts.requests, 0) AS requests
            FROM buckets
            LEFT JOIN session_counts ON session_counts.bucket = buckets.bucket
            LEFT JOIN event_counts ON event_counts.bucket = buckets.bucket
            LEFT JOIN request_counts ON request_counts.bucket = buckets.bucket
            ORDER BY buckets.bucket DESC
            LIMIT {bucket_limit}
            """,
            (interval, interval, interval, interval),
        ).fetchall()
        status_codes = connection.execute(
            """
            SELECT status_code, COUNT(*)::INT AS count
            FROM request_logs
            WHERE occurred_at >= NOW() - %s::interval
            GROUP BY status_code
            ORDER BY count DESC, status_code ASC
            """,
            (interval,),
        ).fetchall()
        country_counts = _label_counts(
            connection,
            """
            SELECT COALESCE(NULLIF(country, ''), 'Unknown') AS label, COUNT(*)::INT AS count
            FROM request_logs
            WHERE occurred_at >= NOW() - %s::interval
            GROUP BY 1
            ORDER BY count DESC, label ASC
            LIMIT 12
            """,
            interval,
        )
        device_breakdown = _label_counts(
            connection,
            f"""
            SELECT {DEVICE_CASE} AS label, COUNT(*)::INT AS count
            FROM request_logs
            WHERE occurred_at >= NOW() - %s::interval
            GROUP BY 1
            ORDER BY count DESC, label ASC
            """,
            interval,
        )
        browser_breakdown = _label_counts(
            connection,
            f"""
            SELECT {BROWSER_CASE} AS label, COUNT(*)::INT AS count
            FROM request_logs
            WHERE occurred_at >= NOW() - %s::interval
            GROUP BY 1
            ORDER BY count DESC, label ASC
            """,
            interval,
        )
        endpoint_breakdown = connection.execute(
            """
            SELECT
                route_group,
                COUNT(*)::INT AS request_count,
                COUNT(*) FILTER (WHERE status_code >= 400)::INT AS error_count,
                COALESCE(AVG(duration_ms), 0)::FLOAT AS average_duration_ms,
                COALESCE(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_ms), 0)::FLOAT AS p95_duration_ms,
                COALESCE(AVG(response_size_bytes), 0)::INT AS average_response_size_bytes
            FROM request_logs
            WHERE occurred_at >= NOW() - %s::interval
            GROUP BY route_group
            ORDER BY request_count DESC, route_group ASC
            LIMIT 16
            """,
            (interval,),
        ).fetchall()
        error_routes = connection.execute(
            """
            SELECT
                route_group,
                COUNT(*) FILTER (WHERE status_code >= 400)::INT AS total_errors,
                COUNT(*) FILTER (WHERE status_code = 404)::INT AS not_found_count,
                COUNT(*) FILTER (WHERE status_code BETWEEN 400 AND 499)::INT AS client_error_count,
                COUNT(*) FILTER (WHERE status_code >= 500)::INT AS server_error_count
            FROM request_logs
            WHERE occurred_at >= NOW() - %s::interval
            GROUP BY route_group
            HAVING COUNT(*) FILTER (WHERE status_code >= 400) > 0
            ORDER BY total_errors DESC, route_group ASC
            LIMIT 12
            """,
            (interval,),
        ).fetchall()
        suspicious_ips = _fetch_suspicious_ips(connection, suspicious_window_minutes)
        recent_requests = connection.execute(
            """
            SELECT
                occurred_at,
                ip,
                method,
                path,
                route_group,
                status_code,
                duration_ms,
                response_size_bytes,
                country,
                visitor_id,
                session_id,
                user_agent,
                referrer,
                request_id
            FROM request_logs
            WHERE occurred_at >= NOW() - %s::interval
            ORDER BY occurred_at DESC
            LIMIT 120
            """,
            (interval,),
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
            WHERE last_seen_at >= NOW() - %s::interval
            ORDER BY last_seen_at DESC
            LIMIT 80
            """,
            (interval,),
        ).fetchall()

    return {
        "generated_at": datetime.now(timezone.utc),
        "window": window,
        "summary": summary,
        "latency": latency,
        "feature_usage": feature_usage,
        "top_referrers": top_referrers,
        "top_landing_paths": top_landing_paths,
        "traffic_buckets": traffic_buckets,
        "status_codes": status_codes,
        "country_counts": country_counts,
        "device_breakdown": device_breakdown,
        "browser_breakdown": browser_breakdown,
        "endpoint_breakdown": endpoint_breakdown,
        "error_routes": error_routes,
        "suspicious_ips": suspicious_ips,
        "recent_requests": recent_requests,
        "recent_sessions": recent_sessions,
    }


def fetch_ip_drilldown(*, window: str, ip: str) -> dict[str, Any]:
    if not analytics_enabled():
        raise HTTPException(status_code=503, detail="Analytics storage is unavailable.")

    interval = _window_interval(window)
    with _connection_pool.connection() as connection:
        summary = connection.execute(
            """
            SELECT
                COUNT(*)::INT AS request_count,
                COUNT(*) FILTER (WHERE status_code >= 400)::INT AS error_count,
                COUNT(DISTINCT session_id)::INT AS session_count,
                COUNT(DISTINCT visitor_id)::INT AS visitor_count,
                COUNT(*) FILTER (WHERE status_code = 404)::INT AS not_found_count,
                COUNT(*) FILTER (WHERE route_group LIKE '/admin%%')::INT AS admin_hit_count,
                ROUND(
                    COUNT(*) * 1.0
                    + COUNT(*) FILTER (WHERE status_code >= 400) * 1.5
                    + COUNT(DISTINCT session_id) * 2.0,
                    2
                ) AS burst_score
            FROM request_logs
            WHERE ip = %s
              AND occurred_at >= NOW() - %s::interval
            """,
            (ip, interval),
        ).fetchone()
        if not summary or summary["request_count"] == 0:
            raise HTTPException(status_code=404, detail="IP not found in analytics window.")

        countries = _label_counts(
            connection,
            """
            SELECT COALESCE(NULLIF(country, ''), 'Unknown') AS label, COUNT(*)::INT AS count
            FROM request_logs
            WHERE ip = %s
              AND occurred_at >= NOW() - %s::interval
            GROUP BY 1
            ORDER BY count DESC, label ASC
            LIMIT 10
            """,
            ip,
            interval,
        )
        user_agents = _label_counts(
            connection,
            """
            SELECT COALESCE(NULLIF(user_agent, ''), 'Unknown') AS label, COUNT(*)::INT AS count
            FROM request_logs
            WHERE ip = %s
              AND occurred_at >= NOW() - %s::interval
            GROUP BY 1
            ORDER BY count DESC
            LIMIT 8
            """,
            ip,
            interval,
        )
        routes = _label_counts(
            connection,
            """
            SELECT route_group AS label, COUNT(*)::INT AS count
            FROM request_logs
            WHERE ip = %s
              AND occurred_at >= NOW() - %s::interval
            GROUP BY 1
            ORDER BY count DESC, label ASC
            LIMIT 12
            """,
            ip,
            interval,
        )
        recent_requests = connection.execute(
            """
            SELECT
                occurred_at,
                ip,
                method,
                path,
                route_group,
                status_code,
                duration_ms,
                response_size_bytes,
                country,
                visitor_id,
                session_id,
                user_agent,
                referrer,
                request_id
            FROM request_logs
            WHERE ip = %s
              AND occurred_at >= NOW() - %s::interval
            ORDER BY occurred_at DESC
            LIMIT 120
            """,
            (ip, interval),
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
            WHERE entry_ip = %s OR last_ip = %s
            ORDER BY last_seen_at DESC
            LIMIT 40
            """,
            (ip, ip),
        ).fetchall()

    return {
        "ip": ip,
        **summary,
        "countries": countries,
        "user_agents": user_agents,
        "routes": routes,
        "recent_requests": recent_requests,
        "recent_sessions": recent_sessions,
    }


def fetch_session_drilldown(*, session_id: str) -> dict[str, Any]:
    if not analytics_enabled():
        raise HTTPException(status_code=503, detail="Analytics storage is unavailable.")

    with _connection_pool.connection() as connection:
        session = connection.execute(
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
            WHERE session_id = %s
            """,
            (session_id,),
        ).fetchone()
        if not session:
            raise HTTPException(status_code=404, detail="Session not found.")

        countries = _label_counts(
            connection,
            """
            SELECT COALESCE(NULLIF(country, ''), 'Unknown') AS label, COUNT(*)::INT AS count
            FROM request_logs
            WHERE session_id = %s
            GROUP BY 1
            ORDER BY count DESC, label ASC
            LIMIT 10
            """,
            session_id,
        )
        routes = _label_counts(
            connection,
            """
            SELECT route_group AS label, COUNT(*)::INT AS count
            FROM request_logs
            WHERE session_id = %s
            GROUP BY 1
            ORDER BY count DESC, label ASC
            LIMIT 12
            """,
            session_id,
        )
        user_agents = _label_counts(
            connection,
            """
            SELECT COALESCE(NULLIF(user_agent, ''), 'Unknown') AS label, COUNT(*)::INT AS count
            FROM request_logs
            WHERE session_id = %s
            GROUP BY 1
            ORDER BY count DESC
            LIMIT 6
            """,
            session_id,
        )
        events = connection.execute(
            """
            SELECT occurred_at, name, path, ip, properties_json AS properties
            FROM events
            WHERE session_id = %s
            ORDER BY occurred_at DESC
            LIMIT 120
            """,
            (session_id,),
        ).fetchall()
        requests = connection.execute(
            """
            SELECT
                occurred_at,
                ip,
                method,
                path,
                route_group,
                status_code,
                duration_ms,
                response_size_bytes,
                country,
                visitor_id,
                session_id,
                user_agent,
                referrer,
                request_id
            FROM request_logs
            WHERE session_id = %s
            ORDER BY occurred_at DESC
            LIMIT 120
            """,
            (session_id,),
        ).fetchall()

    return {
        "session": session,
        "countries": countries,
        "routes": routes,
        "user_agents": user_agents,
        "events": events,
        "requests": requests,
    }


def build_suspicious_csv(*, window: str, suspicious_window_minutes: int) -> str:
    rows = fetch_admin_overview(
        window=window,
        suspicious_window_minutes=suspicious_window_minutes,
    )["suspicious_ips"]
    buffer = StringIO()
    writer = csv.writer(buffer)
    writer.writerow(
        [
            "ip",
            "severity",
            "request_count",
            "error_count",
            "unique_paths",
            "unique_sessions",
            "unique_visitors",
            "not_found_count",
            "admin_hit_count",
            "burst_score",
            "first_seen_at",
            "last_seen_at",
        ]
    )
    for item in rows:
        writer.writerow(
            [
                item["ip"],
                item["severity"],
                item["request_count"],
                item["error_count"],
                item["unique_paths"],
                item["unique_sessions"],
                item["unique_visitors"],
                item["not_found_count"],
                item["admin_hit_count"],
                item["burst_score"],
                item["first_seen_at"],
                item["last_seen_at"],
            ]
        )
    return buffer.getvalue()


def _fetch_suspicious_ips(connection, suspicious_window_minutes: int) -> list[dict[str, Any]]:
    return connection.execute(
        """
        WITH per_minute AS (
            SELECT
                ip,
                DATE_TRUNC('minute', occurred_at) AS minute_bucket,
                COUNT(*)::INT AS minute_requests
            FROM request_logs
            WHERE occurred_at >= NOW() - MAKE_INTERVAL(mins => %s)
              AND ip IS NOT NULL
            GROUP BY ip, minute_bucket
        ),
        per_ip AS (
            SELECT ip, MAX(minute_requests)::INT AS max_minute_requests
            FROM per_minute
            GROUP BY ip
        )
        SELECT
            request_logs.ip,
            COUNT(*)::INT AS request_count,
            COUNT(*) FILTER (WHERE request_logs.status_code >= 400)::INT AS error_count,
            COUNT(DISTINCT request_logs.path)::INT AS unique_paths,
            COUNT(DISTINCT request_logs.session_id)::INT AS unique_sessions,
            COUNT(DISTINCT request_logs.visitor_id)::INT AS unique_visitors,
            COUNT(*) FILTER (WHERE request_logs.status_code = 404)::INT AS not_found_count,
            COUNT(*) FILTER (WHERE request_logs.route_group LIKE '/admin%%')::INT AS admin_hit_count,
            ROUND(
                COALESCE(MAX(per_ip.max_minute_requests), 0) * 2.0
                + COUNT(*) FILTER (WHERE request_logs.status_code >= 400) * 1.5
                + COUNT(*) FILTER (WHERE request_logs.route_group LIKE '/admin%%') * 2.0
                + COUNT(DISTINCT request_logs.session_id) * 1.0,
                2
            ) AS burst_score,
            MIN(request_logs.occurred_at) AS first_seen_at,
            MAX(request_logs.occurred_at) AS last_seen_at,
            CASE
                WHEN COUNT(*) >= 250
                  OR COUNT(*) FILTER (WHERE request_logs.status_code >= 400) >= 80
                  OR COUNT(*) FILTER (WHERE request_logs.route_group LIKE '/admin%%') >= 16
                  OR COALESCE(MAX(per_ip.max_minute_requests), 0) >= 40 THEN 'high'
                WHEN COUNT(*) >= 120
                  OR COUNT(*) FILTER (WHERE request_logs.status_code >= 400) >= 40
                  OR COUNT(*) FILTER (WHERE request_logs.status_code = 404) >= 20
                  OR COALESCE(MAX(per_ip.max_minute_requests), 0) >= 20 THEN 'medium'
                ELSE 'low'
            END AS severity
        FROM request_logs
        LEFT JOIN per_ip ON per_ip.ip = request_logs.ip
        WHERE request_logs.occurred_at >= NOW() - MAKE_INTERVAL(mins => %s)
          AND request_logs.ip IS NOT NULL
        GROUP BY request_logs.ip
        HAVING COUNT(*) >= 50
            OR COUNT(*) FILTER (WHERE request_logs.status_code >= 400) >= 20
            OR COUNT(*) FILTER (WHERE request_logs.status_code = 404) >= 10
            OR COUNT(*) FILTER (WHERE request_logs.route_group LIKE '/admin%%') >= 8
            OR COUNT(DISTINCT request_logs.session_id) >= 12
            OR COALESCE(MAX(per_ip.max_minute_requests), 0) >= 15
        ORDER BY burst_score DESC, request_count DESC, last_seen_at DESC
        LIMIT 30
        """,
        (suspicious_window_minutes, suspicious_window_minutes),
    ).fetchall()


def _label_counts(connection, query: str, *params: Any) -> list[dict[str, Any]]:
    return connection.execute(query, params).fetchall()


def _window_interval(window: str) -> str:
    try:
        return WINDOW_TO_INTERVAL[window]
    except KeyError as error:
        raise HTTPException(status_code=400, detail="Unsupported analytics window.") from error


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
            INSERT INTO visitors (visitor_id, first_ip, last_ip, user_agent)
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
