from fastapi import APIRouter, Query, Request, status

from app.schemas.analytics_models import (
    AdminAnalyticsOverviewResponse,
    AnalyticsEventIngestResponse,
    AnalyticsEventRequest,
)
from app.services.analytics_store import (
    analytics_enabled,
    fetch_admin_overview,
    record_product_event,
    require_admin_token,
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
    window_days: int = Query(default=7, ge=1, le=30),
    suspicious_window_minutes: int = Query(default=60, ge=5, le=1440),
) -> AdminAnalyticsOverviewResponse:
    require_admin_token(request)
    return AdminAnalyticsOverviewResponse(
        **fetch_admin_overview(
            window_days=window_days,
            suspicious_window_minutes=suspicious_window_minutes,
        ),
    )
