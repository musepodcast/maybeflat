from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


class AnalyticsEventRequest(BaseModel):
    visitor_id: str = Field(..., min_length=8, max_length=128)
    session_id: str = Field(..., min_length=8, max_length=128)
    name: str = Field(..., min_length=1, max_length=80)
    path: str | None = Field(default=None, max_length=256)
    referrer: str | None = Field(default=None, max_length=1024)
    properties: dict[str, Any] = Field(default_factory=dict)


class AnalyticsEventIngestResponse(BaseModel):
    accepted: bool
    enabled: bool


class AnalyticsSummaryResponse(BaseModel):
    unique_visitors_24h: int
    sessions_24h: int
    events_24h: int
    requests_24h: int
    error_requests_24h: int
    suspicious_ip_count: int


class AnalyticsCountItemResponse(BaseModel):
    label: str
    count: int


class AnalyticsTrafficDayResponse(BaseModel):
    day: str
    sessions: int
    events: int
    requests: int


class AnalyticsStatusCodeResponse(BaseModel):
    status_code: int
    count: int


class SuspiciousIpActivityResponse(BaseModel):
    ip: str
    request_count: int
    error_count: int
    unique_paths: int
    unique_sessions: int
    first_seen_at: datetime
    last_seen_at: datetime
    severity: str


class RequestLogItemResponse(BaseModel):
    occurred_at: datetime
    ip: str | None = None
    method: str
    path: str
    status_code: int
    duration_ms: int
    country: str | None = None
    visitor_id: str | None = None
    session_id: str | None = None
    user_agent: str | None = None
    referrer: str | None = None
    request_id: str


class SessionItemResponse(BaseModel):
    session_id: str
    visitor_id: str
    started_at: datetime
    last_seen_at: datetime
    landing_path: str | None = None
    referrer: str | None = None
    country: str | None = None
    entry_ip: str | None = None
    last_ip: str | None = None
    request_count: int
    event_count: int


class AdminAnalyticsOverviewResponse(BaseModel):
    generated_at: datetime
    summary: AnalyticsSummaryResponse
    feature_usage: list[AnalyticsCountItemResponse]
    top_referrers: list[AnalyticsCountItemResponse]
    top_landing_paths: list[AnalyticsCountItemResponse]
    traffic_by_day: list[AnalyticsTrafficDayResponse]
    status_codes: list[AnalyticsStatusCodeResponse]
    suspicious_ips: list[SuspiciousIpActivityResponse]
    recent_requests: list[RequestLogItemResponse]
    recent_sessions: list[SessionItemResponse]
