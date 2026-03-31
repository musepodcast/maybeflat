from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routes.map import router as map_router
from app.services.tile_renderer import warm_default_cache


app = FastAPI(
    title="Maybeflat API",
    version="1.0.0",
    description="Backend services for the Maybeflat flat-world mapping model.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
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
