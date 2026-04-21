from fastapi import APIRouter, HTTPException, Query, Response

from app.schemas.map_models import (
    AstronomyEventListResponse,
    AstronomySnapshotResponse,
    CitySearchResponse,
    FlatPointResponse,
    MapLabelResponse,
    MapModelResponse,
    MapSceneResponse,
    MeasureRequest,
    MeasureResponse,
    TileManifestResponse,
    TransformRequest,
    WeatherOverlaySnapshotResponse,
    WindSnapshotResponse,
)
from app.data.city_search import search_city_entries
from app.services.astronomy import get_astronomy_snapshot, list_astronomy_events
from app.services.flat_world import (
    build_model_summary,
    build_scene,
    list_city_labels,
    measure_between_points,
    transform_point,
)
from app.services.tile_renderer import build_tile_manifest, render_tile_png
from app.services.marine_live import (
    LiveMarineDataError,
    get_live_ocean_overlay_snapshot,
)
from app.services.weather_overlays import get_weather_overlay_snapshot
from app.services.weather_wind import get_animation_snapshot, get_wind_snapshot


router = APIRouter(prefix="/map", tags=["map"])


@router.get("/model", response_model=MapModelResponse)
def get_model() -> MapModelResponse:
    return build_model_summary()


@router.get("/scene", response_model=MapSceneResponse)
def get_scene(
    detail: str = Query(default="desktop", pattern="^(mobile|desktop|full)$"),
    include_state_boundaries: bool = Query(default=False),
) -> MapSceneResponse:
    return build_scene(
        detail=detail,
        include_state_boundaries=include_state_boundaries,
    )


@router.get("/tiles/manifest", response_model=TileManifestResponse)
def get_tile_manifest() -> TileManifestResponse:
    return build_tile_manifest()


@router.get("/astronomy", response_model=AstronomySnapshotResponse)
def get_astronomy(
    timestamp_utc: str | None = Query(default=None),
    observer_name: str | None = Query(default=None),
    observer_latitude: float | None = Query(default=None, ge=-90, le=90),
    observer_longitude: float | None = Query(default=None, ge=-180, le=180),
    path_hours: int = Query(default=24, ge=6, le=48),
    path_step_minutes: int = Query(default=30, ge=10, le=120),
) -> AstronomySnapshotResponse:
    if (observer_latitude is None) != (observer_longitude is None):
        raise HTTPException(
            status_code=400,
            detail="observer_latitude and observer_longitude must be provided together.",
        )

    return get_astronomy_snapshot(
        timestamp_utc=timestamp_utc,
        observer_name=observer_name,
        observer_latitude=observer_latitude,
        observer_longitude=observer_longitude,
        path_hours=path_hours,
        path_step_minutes=path_step_minutes,
    )


@router.get("/events", response_model=AstronomyEventListResponse)
def get_events(
    event_type: str | None = Query(default="eclipse"),
    subgroup: str | None = Query(default=None, pattern="^(solar|lunar)?$"),
    from_timestamp_utc: str | None = Query(default=None),
    limit: int = Query(default=24, ge=1, le=64),
) -> AstronomyEventListResponse:
    return list_astronomy_events(
        event_type=event_type,
        subgroup=subgroup,
        from_timestamp_utc=from_timestamp_utc,
        limit=limit,
    )


@router.get("/weather/wind", response_model=WindSnapshotResponse)
def get_weather_wind(
    timestamp_utc: str | None = Query(default=None),
    level: str = Query(
        default="surface",
        pattern="^(surface|1000|850|700|500|250|70|10)$",
    ),
    grid_step_degrees: int = Query(default=15, ge=5, le=30),
) -> WindSnapshotResponse:
    try:
        return get_wind_snapshot(
            timestamp_utc=timestamp_utc,
            level=level,
            grid_step_degrees=grid_step_degrees,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/weather/animate", response_model=WindSnapshotResponse)
def get_weather_animation(
    mode: str = Query(default="wind", pattern="^(wind|currents|waves)$"),
    timestamp_utc: str | None = Query(default=None),
    level: str = Query(
        default="surface",
        pattern="^(surface|1000|850|700|500|250|70|10)$",
    ),
    grid_step_degrees: int = Query(default=15, ge=5, le=30),
) -> WindSnapshotResponse:
    try:
        return get_animation_snapshot(
            mode=mode,
            timestamp_utc=timestamp_utc,
            level=level,
            grid_step_degrees=grid_step_degrees,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except LiveMarineDataError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@router.get("/weather/overlay", response_model=WeatherOverlaySnapshotResponse)
def get_weather_overlay(
    overlay: str = Query(default="wind"),
    timestamp_utc: str | None = Query(default=None),
    level: str = Query(
        default="surface",
        pattern="^(surface|1000|850|700|500|250|70|10)$",
    ),
    grid_step_degrees: int = Query(default=15, ge=5, le=30),
) -> WeatherOverlaySnapshotResponse:
    try:
        return get_weather_overlay_snapshot(
            overlay=overlay,
            timestamp_utc=timestamp_utc,
            level=level,
            grid_step_degrees=grid_step_degrees,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/ocean/overlay", response_model=WeatherOverlaySnapshotResponse)
def get_ocean_overlay(
    overlay: str = Query(default="currents", pattern="^(currents|waves|htsgw|sst|ssta|baa)$"),
    timestamp_utc: str | None = Query(default=None),
    grid_step_degrees: int = Query(default=15, ge=5, le=30),
) -> WeatherOverlaySnapshotResponse:
    try:
        return get_live_ocean_overlay_snapshot(
            overlay=overlay,
            timestamp_utc=timestamp_utc,
            grid_step_degrees=grid_step_degrees,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except LiveMarineDataError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@router.get("/cities/search", response_model=CitySearchResponse)
def get_city_search(
    q: str = Query(default=""),
    limit: int = Query(default=12, ge=1, le=20),
) -> CitySearchResponse:
    results = search_city_entries(q, limit=limit)
    return CitySearchResponse(
        query=q,
        results=[
            {
                "geoname_id": entry.geoname_id,
                "name": entry.name,
                "display_name": entry.display_name,
                "latitude": entry.latitude,
                "longitude": entry.longitude,
                "country_code": entry.country_code,
                "country_name": entry.country_name,
                "admin1_name": entry.admin1_name,
                "population": entry.population,
            }
            for entry in results
        ],
    )


@router.get("/labels/cities", response_model=list[MapLabelResponse])
def get_city_labels(
    min_x: float = Query(...),
    max_x: float = Query(...),
    min_y: float = Query(...),
    max_y: float = Query(...),
    limit: int = Query(default=400, ge=1, le=800),
) -> list[MapLabelResponse]:
    return list_city_labels(
        min_x=min_x,
        max_x=max_x,
        min_y=min_y,
        max_y=max_y,
        limit=limit,
    )


@router.get("/tiles/{edge_mode}/{z}/{x}/{y}.png")
def get_tile(
    edge_mode: str,
    z: int,
    x: int,
    y: int,
) -> Response:
    try:
        tile_bytes = render_tile_png(
            edge_mode=edge_mode,
            z=z,
            x=x,
            y=y,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return Response(
        content=tile_bytes,
        media_type="image/png",
        headers={"Cache-Control": "public, max-age=31536000, immutable"},
    )


@router.get("/tiles/{detail}/{edge_mode}/{z}/{x}/{y}.png")
def get_legacy_tile(
    detail: str,
    edge_mode: str,
    z: int,
    x: int,
    y: int,
) -> Response:
    return get_tile(
        edge_mode=edge_mode,
        z=z,
        x=x,
        y=y,
    )


@router.post("/transform", response_model=FlatPointResponse)
def post_transform(payload: TransformRequest) -> FlatPointResponse:
    return transform_point(payload)


@router.post("/measure", response_model=MeasureResponse)
def post_measure(payload: MeasureRequest) -> MeasureResponse:
    return measure_between_points(payload)
