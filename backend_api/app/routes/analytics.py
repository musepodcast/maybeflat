from fastapi import APIRouter, Query, Request, Response, status

from app.schemas.analytics_models import (
    AdminAnalyticsOverviewResponse,
    AnalyticsEventIngestResponse,
    AnalyticsEventRequest,
    IpDrilldownResponse,
    SessionDrilldownResponse,
)
from app.services.analytics_store import (
    analytics_enabled,
    build_suspicious_csv,
    fetch_admin_overview,
    fetch_ip_drilldown,
    fetch_session_drilldown,
    record_product_event,
    require_admin_access,
)


router = APIRouter(tags=["analytics"])


@router.post(
    "/analytics/events",
    response_model=AnalyticsEventIngestResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
def post_analytics_event(
    payload: AnalyticsEventRequest,
    request: Request,
) -> AnalyticsEventIngestResponse:
    if not analytics_enabled():
        return AnalyticsEventIngestResponse(accepted=False, enabled=False)

    record_product_event(
        request,
        visitor_id=payload.visitor_id,
        session_id=payload.session_id,
        name=payload.name,
        path=payload.path,
        referrer=payload.referrer,
        properties=payload.properties,
    )
    return AnalyticsEventIngestResponse(accepted=True, enabled=True)


@router.get(
    "/admin/analytics/overview",
    response_model=AdminAnalyticsOverviewResponse,
)
def get_admin_analytics_overview(
    request: Request,
    window: str = Query(default="24h", pattern="^(1h|24h|7d|30d)$"),
    suspicious_window_minutes: int = Query(default=60, ge=5, le=1440),
) -> AdminAnalyticsOverviewResponse:
    require_admin_access(request)
    return AdminAnalyticsOverviewResponse(
        **fetch_admin_overview(
            window=window,
            suspicious_window_minutes=suspicious_window_minutes,
        ),
    )


@router.get(
    "/admin/analytics/ip/{ip}",
    response_model=IpDrilldownResponse,
)
def get_admin_ip_drilldown(
    ip: str,
    request: Request,
    window: str = Query(default="24h", pattern="^(1h|24h|7d|30d)$"),
) -> IpDrilldownResponse:
    require_admin_access(request)
    return IpDrilldownResponse(**fetch_ip_drilldown(window=window, ip=ip))


@router.get(
    "/admin/analytics/sessions/{session_id}",
    response_model=SessionDrilldownResponse,
)
def get_admin_session_drilldown(
    session_id: str,
    request: Request,
) -> SessionDrilldownResponse:
    require_admin_access(request)
    return SessionDrilldownResponse(**fetch_session_drilldown(session_id=session_id))


@router.get("/admin/analytics/suspicious.csv")
def download_suspicious_ips_csv(
    request: Request,
    window: str = Query(default="24h", pattern="^(1h|24h|7d|30d)$"),
    suspicious_window_minutes: int = Query(default=60, ge=5, le=1440),
) -> Response:
    require_admin_access(request)
    csv_body = build_suspicious_csv(
        window=window,
        suspicious_window_minutes=suspicious_window_minutes,
    )
    return Response(
        content=csv_body,
        media_type="text/csv",
        headers={
            "Content-Disposition": (
                f'attachment; filename="maybeflat-suspicious-{window}.csv"'
            ),
        },
    )
