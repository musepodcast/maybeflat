from __future__ import annotations

from functools import lru_cache
from datetime import datetime, timezone
from math import atan, atan2, ceil, cos, floor, radians, sin, sqrt, tan
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.data.city_search import build_curated_world_city_labels, load_city_entries
from app.data.coastline_loader import (
    get_state_boundary_dataset_status,
    load_boundary_shapes,
    load_scene_shapes,
    load_state_boundary_labels,
    load_state_boundary_shapes,
    load_timezone_boundary_shapes,
)
from app.data.label_layers import LABEL_LAYERS
from app.data.prototype_scene import SEED_MARKERS
from app.schemas.map_models import (
    FlatPointResponse,
    MapLabelResponse,
    MapModelResponse,
    MapSceneResponse,
    MapShapeResponse,
    MeasureRequest,
    MeasureResponse,
    TransformRequest,
    VectorPointResponse,
    VectorRingResponse,
)

INNER_WORLD_MIN_LATITUDE = -60.0
INNER_WORLD_RADIUS = 0.85
OUTER_RING_RADIUS = 1.0
KILOMETERS_PER_MILE = 1.609344
WGS84_A_METERS = 6_378_137.0
WGS84_F = 1 / 298.257223563
WGS84_B_METERS = (1 - WGS84_F) * WGS84_A_METERS
EARTH_MEAN_RADIUS_METERS = 6_371_008.8
TIME_ZONE_BASE_PALETTE = {
    -12: "#B64E4E",
    -11: "#C35C48",
    -10: "#CF6B45",
    -9: "#DA7C46",
    -8: "#E1914D",
    -7: "#E4A85B",
    -6: "#E2BE68",
    -5: "#D7CA68",
    -4: "#C5CF64",
    -3: "#A9CB62",
    -2: "#88C368",
    -1: "#66BA74",
    0: "#4FB489",
    1: "#47B09C",
    2: "#48ADAE",
    3: "#4DA7BE",
    4: "#589DCA",
    5: "#688FCE",
    6: "#7B82CC",
    7: "#8B78C7",
    8: "#9A70C0",
    9: "#A76AB7",
    10: "#B565AB",
    11: "#C26A9E",
    12: "#CB758F",
    13: "#D18182",
    14: "#D58E7A",
}


def _latitude_to_radius_ratio(latitude: float) -> tuple[float, str]:
    if latitude >= INNER_WORLD_MIN_LATITUDE:
        span = 90.0 - INNER_WORLD_MIN_LATITUDE
        radius_ratio = ((90.0 - latitude) / span) * INNER_WORLD_RADIUS
        return radius_ratio, "inner_world"

    antarctic_span = abs(INNER_WORLD_MIN_LATITUDE - (-90.0))
    antarctic_progress = abs(latitude - INNER_WORLD_MIN_LATITUDE) / antarctic_span
    radius_ratio = INNER_WORLD_RADIUS + antarctic_progress * (
        OUTER_RING_RADIUS - INNER_WORLD_RADIUS
    )
    return radius_ratio, "antarctic_ring"


def _longitude_to_theta(longitude: float) -> float:
    return (-longitude - 90.0) % 360.0


def transform_point(payload: TransformRequest) -> FlatPointResponse:
    radius_ratio, zone = _latitude_to_radius_ratio(payload.latitude)
    theta_degrees = _longitude_to_theta(payload.longitude)
    theta_radians = radians(theta_degrees)

    x = radius_ratio * cos(theta_radians)
    y = radius_ratio * sin(theta_radians)

    return FlatPointResponse(
        name=payload.name,
        latitude=payload.latitude,
        longitude=payload.longitude,
        radius_ratio=round(radius_ratio, 6),
        theta_degrees=round(theta_degrees, 6),
        x=round(x, 6),
        y=round(y, 6),
        zone=zone,
    )


def _transform_coordinates(points: list[tuple[float, float]]) -> list[VectorPointResponse]:
    transformed_points: list[VectorPointResponse] = []
    for latitude, longitude in points:
        radius_ratio, _ = _latitude_to_radius_ratio(latitude)
        theta_degrees = _longitude_to_theta(longitude)
        theta_radians = radians(theta_degrees)

        transformed_points.append(
            VectorPointResponse(
                x=round(radius_ratio * cos(theta_radians), 6),
                y=round(radius_ratio * sin(theta_radians), 6),
            )
        )

    return transformed_points


def _transform_rings(
    rings: list[dict[str, object]],
) -> list[VectorRingResponse]:
    transformed_rings: list[VectorRingResponse] = []
    for ring in rings:
        raw_points = ring.get("points", [])
        if not isinstance(raw_points, list):
            continue
        transformed_points = _transform_coordinates(raw_points)
        if not transformed_points:
            continue
        transformed_rings.append(
            VectorRingResponse(
                closed=bool(ring.get("closed", True)),
                points=transformed_points,
            )
        )

    return transformed_rings


def _label_min_scale(layer: str) -> float:
    if layer == "continent":
        return 1.0
    if layer == "country":
        return 1.8
    if layer == "state":
        return 3.6
    if layer == "city_major":
        return 3.0
    if layer == "city_regional":
        return 5.0
    if layer == "city_local":
        return 7.0
    return 3.0


def _build_scene_labels() -> list[MapLabelResponse]:
    labels: list[MapLabelResponse] = []
    for label in LABEL_LAYERS:
        transformed = transform_point(
            TransformRequest(
                name=label["name"],
                latitude=label["latitude"],
                longitude=label["longitude"],
            )
        )
        labels.append(
            MapLabelResponse(
                name=label["name"],
                layer=label["layer"],
                x=transformed.x,
                y=transformed.y,
                min_scale=float(
                    label.get("min_scale", _label_min_scale(label["layer"]))
                ),
            )
        )
    for label in build_curated_world_city_labels():
        transformed = transform_point(
            TransformRequest(
                name=label.name,
                latitude=label.latitude,
                longitude=label.longitude,
            )
        )
        labels.append(
            MapLabelResponse(
                name=label.name,
                layer=label.layer,
                x=transformed.x,
                y=transformed.y,
                min_scale=label.min_scale,
            )
        )
    return labels


def _build_state_labels() -> list[MapLabelResponse]:
    raw_labels, _, _ = load_state_boundary_labels()
    labels: list[MapLabelResponse] = []
    for label in raw_labels:
        transformed = transform_point(
            TransformRequest(
                name=str(label["name"]),
                latitude=float(label["latitude"]),
                longitude=float(label["longitude"]),
            )
        )
        labels.append(
            MapLabelResponse(
                name=str(label["name"]),
                layer="state",
                x=transformed.x,
                y=transformed.y,
                min_scale=float(label.get("min_scale", _label_min_scale("state"))),
            )
        )
    return labels


@lru_cache(maxsize=1)
def _build_city_detail_labels() -> tuple[MapLabelResponse, ...]:
    labels: list[MapLabelResponse] = []
    for entry in load_city_entries():
        transformed = transform_point(
            TransformRequest(
                name=entry.name,
                latitude=entry.latitude,
                longitude=entry.longitude,
            )
        )
        labels.append(
            MapLabelResponse(
                name=entry.name,
                layer="city_detail",
                x=transformed.x,
                y=transformed.y,
                min_scale=5.6,
            )
        )
    return tuple(labels)


def list_city_labels(
    *,
    min_x: float,
    max_x: float,
    min_y: float,
    max_y: float,
    limit: int = 400,
) -> list[MapLabelResponse]:
    left = min(min_x, max_x)
    right = max(min_x, max_x)
    top = min(min_y, max_y)
    bottom = max(min_y, max_y)

    results: list[MapLabelResponse] = []
    for label in _build_city_detail_labels():
        if label.x < left or label.x > right or label.y < top or label.y > bottom:
            continue
        results.append(label)
        if len(results) >= limit:
            break

    return results


def _format_time_zone_label(offset_minutes: int) -> str:
    if offset_minutes == 0:
        return "UTC"

    sign = "+" if offset_minutes > 0 else "-"
    absolute_minutes = abs(offset_minutes)
    hours, minutes = divmod(absolute_minutes, 60)
    if minutes == 0:
        return f"UTC{sign}{hours}"
    return f"UTC{sign}{hours}:{minutes:02d}"


def _hex_to_rgb(hex_value: str) -> tuple[int, int, int]:
    normalized = hex_value.replace("#", "")
    return (
        int(normalized[0:2], 16),
        int(normalized[2:4], 16),
        int(normalized[4:6], 16),
    )


def _rgb_to_hex(red: int, green: int, blue: int) -> str:
    return "#{:02X}{:02X}{:02X}".format(red, green, blue)


def _mix_hex_colors(left: str, right: str, fraction: float) -> str:
    left_red, left_green, left_blue = _hex_to_rgb(left)
    right_red, right_green, right_blue = _hex_to_rgb(right)
    mixed_red = round(left_red + (right_red - left_red) * fraction)
    mixed_green = round(left_green + (right_green - left_green) * fraction)
    mixed_blue = round(left_blue + (right_blue - left_blue) * fraction)
    return _rgb_to_hex(mixed_red, mixed_green, mixed_blue)


def _darken_hex_color(hex_value: str, factor: float) -> str:
    red, green, blue = _hex_to_rgb(hex_value)
    return _rgb_to_hex(
        round(red * factor),
        round(green * factor),
        round(blue * factor),
    )


def _time_zone_offset_minutes(time_zone_name: str) -> int | None:
    try:
        zone = ZoneInfo(time_zone_name)
    except ZoneInfoNotFoundError:
        return None

    now_utc = datetime.now(timezone.utc)
    offset = now_utc.astimezone(zone).utcoffset()
    if offset is None:
        return None
    return int(offset.total_seconds() // 60)


def _time_zone_fill_and_stroke(offset_minutes: int) -> tuple[str, str]:
    raw_hours = max(-12.0, min(14.0, offset_minutes / 60))
    lower_hour = max(-12, min(14, floor(raw_hours)))
    upper_hour = max(-12, min(14, ceil(raw_hours)))
    lower_color = TIME_ZONE_BASE_PALETTE[lower_hour]
    upper_color = TIME_ZONE_BASE_PALETTE[upper_hour]
    if lower_hour == upper_hour:
      fill = lower_color
    else:
      fill = _mix_hex_colors(lower_color, upper_color, raw_hours - lower_hour)
    stroke = _darken_hex_color(fill, 0.58)
    return fill, stroke


def _build_timezone_shape(shape: dict[str, object]) -> MapShapeResponse:
    timezone_name = str(shape["name"])
    offset_minutes = _time_zone_offset_minutes(timezone_name)
    fill = str(shape["fill"])
    stroke = str(shape["stroke"])
    label: str | None = None
    if offset_minutes is not None:
        label = _format_time_zone_label(offset_minutes)
        fill, stroke = _time_zone_fill_and_stroke(offset_minutes)

    return MapShapeResponse(
        name=timezone_name,
        role=str(shape.get("role", "timezone")),
        fill=fill,
        stroke=stroke,
        rings=_transform_rings(shape["rings"]),
        time_zone_label=label,
        time_zone_offset_minutes=offset_minutes,
    )


def _haversine_distance_km(
    start_latitude: float,
    start_longitude: float,
    end_latitude: float,
    end_longitude: float,
) -> float:
    phi1 = radians(start_latitude)
    phi2 = radians(end_latitude)
    delta_phi = radians(end_latitude - start_latitude)
    delta_lambda = radians(end_longitude - start_longitude)

    a = (
        sin(delta_phi / 2) ** 2
        + cos(phi1) * cos(phi2) * sin(delta_lambda / 2) ** 2
    )
    c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return (EARTH_MEAN_RADIUS_METERS * c) / 1000


def _geodesic_distance_km(
    start_latitude: float,
    start_longitude: float,
    end_latitude: float,
    end_longitude: float,
) -> float:
    if (
        start_latitude == end_latitude
        and start_longitude == end_longitude
    ):
        return 0.0

    phi1 = radians(start_latitude)
    phi2 = radians(end_latitude)
    l = radians(end_longitude - start_longitude)
    reduced_latitude_1 = atan((1 - WGS84_F) * tan(phi1))
    reduced_latitude_2 = atan((1 - WGS84_F) * tan(phi2))
    sin_u1 = sin(reduced_latitude_1)
    cos_u1 = cos(reduced_latitude_1)
    sin_u2 = sin(reduced_latitude_2)
    cos_u2 = cos(reduced_latitude_2)

    lambda_value = l
    for _ in range(200):
        sin_lambda = sin(lambda_value)
        cos_lambda = cos(lambda_value)
        sin_sigma = sqrt(
            (cos_u2 * sin_lambda) ** 2
            + (cos_u1 * sin_u2 - sin_u1 * cos_u2 * cos_lambda) ** 2
        )
        if sin_sigma == 0:
            return 0.0

        cos_sigma = sin_u1 * sin_u2 + cos_u1 * cos_u2 * cos_lambda
        sigma = atan2(sin_sigma, cos_sigma)
        sin_alpha = (cos_u1 * cos_u2 * sin_lambda) / sin_sigma
        cos_sq_alpha = 1 - sin_alpha * sin_alpha
        cos_2sigma_m = (
            0.0
            if cos_sq_alpha == 0
            else cos_sigma - (2 * sin_u1 * sin_u2) / cos_sq_alpha
        )
        c = (WGS84_F / 16) * cos_sq_alpha * (4 + WGS84_F * (4 - 3 * cos_sq_alpha))
        previous_lambda = lambda_value
        lambda_value = l + (1 - c) * WGS84_F * sin_alpha * (
            sigma
            + c
            * sin_sigma
            * (
                cos_2sigma_m
                + c * cos_sigma * (-1 + 2 * cos_2sigma_m * cos_2sigma_m)
            )
        )

        if abs(lambda_value - previous_lambda) < 1e-12:
            break
    else:
        return _haversine_distance_km(
            start_latitude,
            start_longitude,
            end_latitude,
            end_longitude,
        )

    u_sq = cos_sq_alpha * (
        (WGS84_A_METERS * WGS84_A_METERS - WGS84_B_METERS * WGS84_B_METERS)
        / (WGS84_B_METERS * WGS84_B_METERS)
    )
    a = 1 + (u_sq / 16384) * (
        4096 + u_sq * (-768 + u_sq * (320 - 175 * u_sq))
    )
    b = (u_sq / 1024) * (
        256 + u_sq * (-128 + u_sq * (74 - 47 * u_sq))
    )
    delta_sigma = b * sin_sigma * (
        cos_2sigma_m
        + (b / 4)
        * (
            cos_sigma * (-1 + 2 * cos_2sigma_m * cos_2sigma_m)
            - (b / 6)
            * cos_2sigma_m
            * (-3 + 4 * sin_sigma * sin_sigma)
            * (-3 + 4 * cos_2sigma_m * cos_2sigma_m)
        )
    )
    distance_meters = WGS84_B_METERS * a * (sigma - delta_sigma)
    return distance_meters / 1000


def measure_between_points(payload: MeasureRequest) -> MeasureResponse:
    start = transform_point(
        TransformRequest(
            latitude=payload.start_latitude,
            longitude=payload.start_longitude,
        )
    )
    end = transform_point(
        TransformRequest(
            latitude=payload.end_latitude,
            longitude=payload.end_longitude,
        )
    )

    dx = end.x - start.x
    dy = end.y - start.y
    plane_distance = sqrt(dx * dx + dy * dy)
    geodesic_distance_km = _geodesic_distance_km(
        payload.start_latitude,
        payload.start_longitude,
        payload.end_latitude,
        payload.end_longitude,
    )
    geodesic_distance_miles = geodesic_distance_km / KILOMETERS_PER_MILE

    return MeasureResponse(
        start=start,
        end=end,
        plane_distance=round(plane_distance, 6),
        plane_distance_label=f"{plane_distance:.3f} map units",
        geodesic_distance_km=round(geodesic_distance_km, 2),
        geodesic_distance_miles=round(geodesic_distance_miles, 2),
        distance_reference_note=(
            "Miles and kilometers use WGS84 geodesic distance from the source "
            "latitude/longitude, while map units remain Maybeflat plane distance."
        ),
    )


@lru_cache(maxsize=16)
def _build_scene_cached(detail: str, include_state_boundaries: bool) -> MapSceneResponse:
    raw_shapes, shape_source, using_real_coastlines = load_scene_shapes(detail=detail)
    raw_boundary_shapes, boundary_source, using_country_boundaries = (
        load_boundary_shapes(detail=detail)
    )
    raw_timezone_shapes, timezone_source, using_real_timezones = (
        load_timezone_boundary_shapes(detail=detail)
    )
    if include_state_boundaries:
        raw_state_boundary_shapes, state_boundary_source, using_state_boundaries = (
            load_state_boundary_shapes(detail=detail)
        )
    else:
        raw_state_boundary_shapes = []
        state_boundary_source, using_state_boundaries = (
            get_state_boundary_dataset_status()
        )

    markers = [
        transform_point(
            TransformRequest(
                name=marker["name"],
                latitude=marker["latitude"],
                longitude=marker["longitude"],
            )
        )
        for marker in SEED_MARKERS
    ]

    shapes = [
        MapShapeResponse(
            name=shape["name"],
            role=shape.get("role", "land"),
            fill=shape["fill"],
            stroke=shape["stroke"],
            rings=_transform_rings(shape["rings"]),
        )
        for shape in raw_shapes
        if shape.get("rings")
    ]
    boundary_shapes = [
        MapShapeResponse(
            name=shape["name"],
            role=shape.get("role", "boundary"),
            fill=shape["fill"],
            stroke=shape["stroke"],
            rings=_transform_rings(shape["rings"]),
        )
        for shape in raw_boundary_shapes
        if shape.get("rings")
    ]
    state_boundary_shapes = [
        MapShapeResponse(
            name=shape["name"],
            role=shape.get("role", "state_boundary"),
            fill=shape["fill"],
            stroke=shape["stroke"],
            rings=_transform_rings(shape["rings"]),
        )
        for shape in raw_state_boundary_shapes
        if shape.get("rings")
    ]
    timezone_shapes = [
        _build_timezone_shape(shape)
        for shape in raw_timezone_shapes
        if shape.get("rings")
    ]
    labels = _build_scene_labels()
    if include_state_boundaries:
        labels.extend(_build_state_labels())

    return MapSceneResponse(
        markers=markers,
        shapes=[*shapes, *boundary_shapes, *state_boundary_shapes, *timezone_shapes],
        labels=labels,
        shape_source=shape_source,
        using_real_coastlines=using_real_coastlines,
        boundary_source=boundary_source,
        using_country_boundaries=using_country_boundaries,
        state_boundary_source=state_boundary_source,
        using_state_boundaries=using_state_boundaries,
        timezone_source=timezone_source,
        using_real_timezones=using_real_timezones,
        detail_level=detail,
    )


def build_scene(
    detail: str = "desktop",
    include_state_boundaries: bool = False,
) -> MapSceneResponse:
    return _build_scene_cached(detail, include_state_boundaries)


def build_model_summary() -> MapModelResponse:
    return MapModelResponse(
        name="Maybeflat",
        version="1.0.0",
        center_rule="North Pole is fixed at the center of the plane.",
        antarctica_rule=(
            "Latitudes south of -60 are mapped into the outer perimeter ring."
        ),
        distance_rule="Distance is Euclidean on the transformed plane.",
        notes=[
            "This model is custom to the project.",
            "Source latitude and longitude are used only as input material.",
            "Raster or vector map layers can be generated against this transform.",
        ],
    )
