import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routes.map import router as map_router
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


@app.on_event("startup")
def warm_runtime_caches() -> None:
    print("Warming Maybeflat scene and tile caches...")
    warm_default_cache()
    print("Maybeflat cache warmup complete.")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
