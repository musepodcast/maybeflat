from pydantic import BaseModel, Field


class TransformRequest(BaseModel):
    name: str | None = Field(default=None, description="Optional display name.")
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)


class FlatPointResponse(BaseModel):
    name: str | None = None
    latitude: float
    longitude: float
    radius_ratio: float
    theta_degrees: float
    x: float
    y: float
    zone: str


class VectorPointResponse(BaseModel):
    x: float
    y: float


class VectorRingResponse(BaseModel):
    closed: bool = True
    points: list[VectorPointResponse]


class MapShapeResponse(BaseModel):
    name: str
    role: str = "land"
    fill: str
    stroke: str
    rings: list[VectorRingResponse]
    time_zone_label: str | None = None
    time_zone_offset_minutes: int | None = None


class MapLabelResponse(BaseModel):
    name: str
    layer: str
    x: float
    y: float
    min_scale: float


class MeasureRequest(BaseModel):
    start_latitude: float = Field(..., ge=-90, le=90)
    start_longitude: float = Field(..., ge=-180, le=180)
    end_latitude: float = Field(..., ge=-90, le=90)
    end_longitude: float = Field(..., ge=-180, le=180)


class MeasureResponse(BaseModel):
    start: FlatPointResponse
    end: FlatPointResponse
    plane_distance: float
    plane_distance_label: str
    geodesic_distance_km: float
    geodesic_distance_miles: float
    distance_reference_note: str


class MapModelResponse(BaseModel):
    name: str
    version: str
    center_rule: str
    antarctica_rule: str
    distance_rule: str
    notes: list[str]


class MapSceneResponse(BaseModel):
    markers: list[FlatPointResponse]
    shapes: list[MapShapeResponse]
    labels: list[MapLabelResponse]
    shape_source: str
    using_real_coastlines: bool
    boundary_source: str
    using_country_boundaries: bool
    state_boundary_source: str
    using_state_boundaries: bool
    timezone_source: str
    using_real_timezones: bool
    detail_level: str


class TileManifestResponse(BaseModel):
    tile_size: int
    max_zoom: int
    world_min: float
    world_max: float
    edge_modes: list[str]
    tile_set: str
    url_template: str


class AstronomyBodyResponse(BaseModel):
    name: str
    subpoint: FlatPointResponse
    path: list[FlatPointResponse]
    phase_name: str | None = None
    illumination_fraction: float | None = None


class AstronomyObserverResponse(BaseModel):
    name: str | None = None
    latitude: float
    longitude: float
    sun_altitude_degrees: float
    moon_altitude_degrees: float
    is_daylight: bool
    is_moon_visible: bool
    moon_illumination_fraction: float


class AstronomySnapshotResponse(BaseModel):
    timestamp_utc: str
    source: str
    greenwich_sidereal_degrees: float
    sun: AstronomyBodyResponse
    moon: AstronomyBodyResponse
    planets: list[AstronomyBodyResponse] = Field(default_factory=list)
    observer: AstronomyObserverResponse | None = None


class AstronomyEventResponse(BaseModel):
    id: str
    event_type: str
    subtype: str
    title: str
    timestamp_utc: str
    description: str | None = None


class AstronomyEventListResponse(BaseModel):
    events: list[AstronomyEventResponse]


class WindVectorResponse(BaseModel):
    latitude: float
    longitude: float
    u_mps: float
    v_mps: float
    speed_mps: float


class WindSnapshotResponse(BaseModel):
    timestamp_utc: str
    source: str
    level: str
    grid_step_degrees: int
    min_speed_mps: float
    max_speed_mps: float
    vectors: list[WindVectorResponse]


class CitySearchResultResponse(BaseModel):
    geoname_id: int
    name: str
    display_name: str
    latitude: float
    longitude: float
    country_code: str
    country_name: str
    admin1_name: str | None = None
    population: int


class CitySearchResponse(BaseModel):
    query: str
    results: list[CitySearchResultResponse]
