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
    unique_visitors: int
    sessions: int
    events: int
    requests: int
    error_requests: int
    suspicious_ip_count: int


class AnalyticsCountItemResponse(BaseModel):
    label: str
    count: int


class FeatureUsageItemResponse(BaseModel):
    label: str
    count: int
    success_count: int
    failure_count: int


class AnalyticsTrafficBucketResponse(BaseModel):
    bucket: str
    sessions: int
    events: int
    requests: int


class AnalyticsStatusCodeResponse(BaseModel):
    status_code: int
    count: int


class AnalyticsLatencySummaryResponse(BaseModel):
    average_ms: float
    p50_ms: float
    p95_ms: float
    p99_ms: float
    average_response_size_bytes: int


class EndpointBreakdownItemResponse(BaseModel):
    route_group: str
    request_count: int
    error_count: int
    average_duration_ms: float
    p95_duration_ms: float
    average_response_size_bytes: int


class ErrorRouteItemResponse(BaseModel):
    route_group: str
    total_errors: int
    not_found_count: int
    client_error_count: int
    server_error_count: int


class SuspiciousIpActivityResponse(BaseModel):
    ip: str
    request_count: int
    error_count: int
    unique_paths: int
    unique_sessions: int
    unique_visitors: int
    not_found_count: int
    admin_hit_count: int
    burst_score: float
    first_seen_at: datetime
    last_seen_at: datetime
    severity: str


class RequestLogItemResponse(BaseModel):
    occurred_at: datetime
    ip: str | None = None
    method: str
    path: str
    route_group: str
    status_code: int
    duration_ms: int
    response_size_bytes: int
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


class SessionEventItemResponse(BaseModel):
    occurred_at: datetime
    name: str
    path: str | None = None
    ip: str | None = None
    properties: dict[str, Any] = Field(default_factory=dict)


class IpDrilldownResponse(BaseModel):
    ip: str
    request_count: int
    error_count: int
    session_count: int
    visitor_count: int
    not_found_count: int
    admin_hit_count: int
    burst_score: float
    countries: list[AnalyticsCountItemResponse]
    user_agents: list[AnalyticsCountItemResponse]
    routes: list[AnalyticsCountItemResponse]
    recent_requests: list[RequestLogItemResponse]
    recent_sessions: list[SessionItemResponse]


class SessionDrilldownResponse(BaseModel):
    session: SessionItemResponse
    countries: list[AnalyticsCountItemResponse]
    routes: list[AnalyticsCountItemResponse]
    user_agents: list[AnalyticsCountItemResponse]
    events: list[SessionEventItemResponse]
    requests: list[RequestLogItemResponse]


class AdminAnalyticsOverviewResponse(BaseModel):
    generated_at: datetime
    window: str
    summary: AnalyticsSummaryResponse
    latency: AnalyticsLatencySummaryResponse
    feature_usage: list[FeatureUsageItemResponse]
    top_referrers: list[AnalyticsCountItemResponse]
    top_landing_paths: list[AnalyticsCountItemResponse]
    traffic_buckets: list[AnalyticsTrafficBucketResponse]
    status_codes: list[AnalyticsStatusCodeResponse]
    country_counts: list[AnalyticsCountItemResponse]
    device_breakdown: list[AnalyticsCountItemResponse]
    browser_breakdown: list[AnalyticsCountItemResponse]
    endpoint_breakdown: list[EndpointBreakdownItemResponse]
    error_routes: list[ErrorRouteItemResponse]
    suspicious_ips: list[SuspiciousIpActivityResponse]
    recent_requests: list[RequestLogItemResponse]
    recent_sessions: list[SessionItemResponse]
