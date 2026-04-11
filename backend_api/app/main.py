import os

from contextlib import suppress
from time import perf_counter

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routes.analytics import router as analytics_router
from app.routes.map import router as map_router
from app.services.analytics_store import (
    build_request_id,
    close_analytics_storage,
    initialize_analytics_storage,
    track_request,
)
from app.services.tile_renderer import warm_default_cache


app = FastAPI(
    title="Maybeflat API",
    version="1.0.0",
    description="Backend services for the Maybeflat flat-world mapping model.",
)


def _parse_allowed_origins() -> list[str]:
    configured = os.getenv("MAYBEFLAT_ALLOWED_ORIGINS", "").strip()
    if configured:
        return [origin.strip() for origin in configured.split(",") if origin.strip()]

    return [
        "http://localhost:3000",
        "http://localhost:5173",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:5173",
        "http://127.0.0.1:8000",
        "http://127.0.0.1:8002",
        "https://maybeflat.com",
        "https://www.maybeflat.com",
    ]


def _parse_allowed_origin_regex() -> str | None:
    configured = os.getenv("MAYBEFLAT_ALLOWED_ORIGIN_REGEX", "").strip()
    if configured:
        return configured

    return r"^https:\/\/.*\.pages\.dev$"


app.add_middleware(
    CORSMiddleware,
    allow_origins=_parse_allowed_origins(),
    allow_origin_regex=_parse_allowed_origin_regex(),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(map_router)
app.include_router(analytics_router)


@app.middleware("http")
async def log_requests(request, call_next):
    request_id = build_request_id(request)
    started_at = perf_counter()
    try:
        response = await call_next(request)
    except Exception:
        duration_ms = int((perf_counter() - started_at) * 1000)
        with suppress(Exception):
            track_request(
                request,
                status_code=500,
                duration_ms=duration_ms,
                request_id=request_id,
            )
        raise

    duration_ms = int((perf_counter() - started_at) * 1000)
    response.headers["X-Request-ID"] = request_id
    with suppress(Exception):
        track_request(
            request,
            status_code=response.status_code,
            duration_ms=duration_ms,
            request_id=request_id,
        )
    return response


@app.on_event("startup")
def warm_runtime_caches() -> None:
    initialize_analytics_storage()
    print("Warming Maybeflat scene and tile caches...")
    warm_default_cache()
    print("Maybeflat cache warmup complete.")


@app.on_event("shutdown")
def close_runtime_resources() -> None:
    close_analytics_storage()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
