from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from app.data.prototype_scene import VECTOR_SHAPES

DEFAULT_FILL = "#F0C96B"
DEFAULT_STROKE = "#173042"
ANTARCTIC_FILL = "#F8FBF6"
ANTARCTIC_STROKE = "#DCEFF4"
BOUNDARY_FILL = "#00000000"
BOUNDARY_STROKE = "#204A60"
STATE_BOUNDARY_FILL = "#00000000"
STATE_BOUNDARY_STROKE = "#557C8B"
TIMEZONE_FILL = "#00000000"
TIMEZONE_STROKE = "#5B7381"
STATE_LABEL_COUNTRY_CODES = {
    "AR",
    "AU",
    "BR",
    "CA",
    "IN",
    "MX",
    "US",
}
DETAIL_POINT_LIMITS = {
    "mobile": 180,
    "desktop": 1400,
    "full": None,
}


def get_coastline_dataset_path() -> Path:
    repo_root = Path(__file__).resolve().parents[3]
    return repo_root / "docs" / "data" / "coastlines.geojson"


def get_country_boundary_dataset_path() -> Path:
    repo_root = Path(__file__).resolve().parents[3]
    return repo_root / "docs" / "data" / "country_boundaries.geojson"


def get_state_boundary_dataset_path() -> Path:
    repo_root = Path(__file__).resolve().parents[3]
    return repo_root / "docs" / "data" / "state_boundaries.geojson"


def get_timezone_boundary_dataset_path() -> Path:
    repo_root = Path(__file__).resolve().parents[3]
    return repo_root / "docs" / "data" / "timezone_boundaries.geojson"


def get_state_boundary_dataset_status() -> tuple[str, bool]:
    dataset_path = get_state_boundary_dataset_path()
    if not dataset_path.exists():
        return "unavailable", False
    return dataset_path.name, True


def get_timezone_boundary_dataset_status() -> tuple[str, bool]:
    dataset_path = get_timezone_boundary_dataset_path()
    if not dataset_path.exists():
        return "unavailable", False
    return dataset_path.name, True


def load_scene_shapes(detail: str = "desktop") -> tuple[list[dict[str, Any]], str, bool]:
    dataset_path = get_coastline_dataset_path()
    if not dataset_path.exists():
        return VECTOR_SHAPES, "prototype", False

    with dataset_path.open("r", encoding="utf-8") as handle:
        raw = json.load(handle)

    shapes = _geojson_to_shapes(raw, detail=detail, role="land")
    if not shapes:
        return VECTOR_SHAPES, "prototype", False

    return shapes, dataset_path.name, True


def load_boundary_shapes(detail: str = "desktop") -> tuple[list[dict[str, Any]], str, bool]:
    dataset_path = get_country_boundary_dataset_path()
    if not dataset_path.exists():
        return [], "unavailable", False

    with dataset_path.open("r", encoding="utf-8") as handle:
        raw = json.load(handle)

    shapes = _geojson_to_shapes(
        raw,
        detail=detail,
        role="boundary",
        default_fill=BOUNDARY_FILL,
        default_stroke=BOUNDARY_STROKE,
    )
    if not shapes:
        return [], dataset_path.name, False

    return shapes, dataset_path.name, True


def load_state_boundary_shapes(detail: str = "desktop") -> tuple[list[dict[str, Any]], str, bool]:
    dataset_path = get_state_boundary_dataset_path()
    if not dataset_path.exists():
        return [], "unavailable", False

    with dataset_path.open("r", encoding="utf-8") as handle:
        raw = json.load(handle)

    shapes = _geojson_to_shapes(
        raw,
        detail=detail,
        role="state_boundary",
        default_fill=STATE_BOUNDARY_FILL,
        default_stroke=STATE_BOUNDARY_STROKE,
    )
    if not shapes:
        return [], dataset_path.name, False

    return shapes, dataset_path.name, True


def load_state_boundary_labels() -> tuple[list[dict[str, object]], str, bool]:
    dataset_path = get_state_boundary_dataset_path()
    if not dataset_path.exists():
        return [], "unavailable", False

    with dataset_path.open("r", encoding="utf-8") as handle:
        raw = json.load(handle)

    payload_type = raw.get("type")
    if payload_type == "FeatureCollection":
        features = raw.get("features", [])
    elif payload_type == "Feature":
        features = [raw]
    else:
        features = []

    labels: list[dict[str, object]] = []
    seen_keys: set[tuple[str, str]] = set()
    for feature in features:
        properties = feature.get("properties") or {}
        iso_a2 = str(properties.get("iso_a2") or "").upper()
        if iso_a2 not in STATE_LABEL_COUNTRY_CODES:
            continue

        latitude = properties.get("latitude")
        longitude = properties.get("longitude")
        if latitude is None or longitude is None:
            continue

        try:
            latitude_value = float(latitude)
            longitude_value = float(longitude)
        except (TypeError, ValueError):
            continue

        label_name = (
            properties.get("name_en")
            or properties.get("name")
            or properties.get("postal")
            or properties.get("iso_3166_2")
        )
        if not label_name:
            continue

        normalized_name = _normalize_label_name(str(label_name).strip())
        if not normalized_name:
            continue

        dedupe_key = (iso_a2, normalized_name)
        if dedupe_key in seen_keys:
            continue
        seen_keys.add(dedupe_key)

        labels.append(
            {
                "name": normalized_name,
                "latitude": latitude_value,
                "longitude": longitude_value,
                "layer": "state",
                "min_scale": 3.6,
            }
        )

    return labels, dataset_path.name, bool(labels)


def _normalize_label_name(value: str) -> str:
    if any(marker in value for marker in ("Ã", "Â", "Ð", "Ø", "à")):
        try:
            repaired = value.encode("latin-1").decode("utf-8")
            if repaired:
                return repaired
        except UnicodeError:
            pass
    return value


def load_timezone_boundary_shapes(
    detail: str = "desktop",
) -> tuple[list[dict[str, Any]], str, bool]:
    dataset_path = get_timezone_boundary_dataset_path()
    if not dataset_path.exists():
        return [], "unavailable", False

    with dataset_path.open("r", encoding="utf-8") as handle:
        raw = json.load(handle)

    shapes = _geojson_to_shapes(
        raw,
        detail=detail,
        role="timezone",
        default_fill=TIMEZONE_FILL,
        default_stroke=TIMEZONE_STROKE,
    )
    if not shapes:
        return [], dataset_path.name, False

    return shapes, dataset_path.name, True


def _geojson_to_shapes(
    payload: dict[str, Any],
    *,
    detail: str,
    role: str,
    default_fill: str = DEFAULT_FILL,
    default_stroke: str = DEFAULT_STROKE,
) -> list[dict[str, Any]]:
    payload_type = payload.get("type")
    if payload_type == "FeatureCollection":
        features = payload.get("features", [])
    elif payload_type == "Feature":
        features = [payload]
    else:
        features = [{"type": "Feature", "geometry": payload, "properties": {}}]

    shapes: list[dict[str, Any]] = []
    for index, feature in enumerate(features):
        geometry = feature.get("geometry")
        if not geometry:
            continue

        properties = feature.get("properties") or {}
        shapes.extend(
            _geometry_to_shapes(
                geometry,
                properties,
                index,
                detail=detail,
                role=role,
                default_fill=default_fill,
                default_stroke=default_stroke,
            )
        )

    return shapes


def _geometry_to_shapes(
    geometry: dict[str, Any],
    properties: dict[str, Any],
    feature_index: int,
    *,
    detail: str,
    role: str,
    default_fill: str,
    default_stroke: str,
) -> list[dict[str, Any]]:
    geometry_type = geometry.get("type")
    coordinates = geometry.get("coordinates")
    name = (
        properties.get("tzid")
        or properties.get("TZID")
        or properties.get("zone")
        or properties.get("name")
        or properties.get("NAME")
        or f"Coast {feature_index + 1}"
    )
    fill = properties.get("fill") or default_fill
    stroke = properties.get("stroke") or default_stroke

    if geometry_type == "Polygon":
        rings = coordinates or []
        if not rings:
            return []
        return [
            _build_shape(
                name=name,
                fill=fill,
                stroke=stroke,
                rings=rings,
                detail=detail,
                role=role,
            )
        ]

    if geometry_type == "MultiPolygon":
        shapes: list[dict[str, Any]] = []
        for polygon_index, polygon in enumerate(coordinates or [], start=1):
            if not polygon:
                continue
            shapes.append(
                _build_shape(
                    name=f"{name} {polygon_index}",
                    fill=fill,
                    stroke=stroke,
                    rings=polygon,
                    detail=detail,
                    role=role,
                )
            )
        return shapes

    if geometry_type == "LineString":
        return [
            _build_shape(
                name=name,
                fill=fill,
                stroke=stroke,
                rings=[coordinates or []],
                detail=detail,
                closed=False,
                role=role,
            )
        ]

    if geometry_type == "MultiLineString":
        shapes = []
        for line_index, line in enumerate(coordinates or [], start=1):
            shapes.append(
                _build_shape(
                    name=f"{name} {line_index}",
                    fill=fill,
                    stroke=stroke,
                    rings=[line],
                    detail=detail,
                    closed=False,
                    role=role,
                )
            )
        return shapes

    if geometry_type == "GeometryCollection":
        shapes = []
        for nested_index, nested in enumerate(geometry.get("geometries") or []):
            shapes.extend(
                _geometry_to_shapes(
                    nested,
                    properties={**properties, "name": f"{name} {nested_index + 1}"},
                    feature_index=feature_index,
                    detail=detail,
                    role=role,
                    default_fill=default_fill,
                    default_stroke=default_stroke,
                )
            )
        return shapes

    return []


def _build_shape(
    *,
    name: str,
    fill: str,
    stroke: str,
    rings: list[list[list[float]]],
    detail: str,
    role: str,
    closed: bool = True,
) -> dict[str, Any]:
    if role == "land" and _is_antarctic_geometry(rings):
        fill = ANTARCTIC_FILL
        stroke = ANTARCTIC_STROKE

    normalized_rings = [
        {
            "closed": closed,
            "points": _normalize_coordinates(ring, detail=detail),
        }
        for ring in rings
        if ring
    ]

    return {
        "name": name,
        "role": role,
        "fill": fill,
        "stroke": stroke,
        "rings": [ring for ring in normalized_rings if ring["points"]],
    }


def _is_antarctic_geometry(rings: list[list[list[float]]]) -> bool:
    max_latitude: float | None = None
    for ring in rings:
        for coordinate in ring:
            if len(coordinate) < 2:
                continue
            latitude = float(coordinate[1])
            if max_latitude is None or latitude > max_latitude:
                max_latitude = latitude

    return max_latitude is not None and max_latitude <= -60.0


def _normalize_coordinates(
    coordinates: list[list[float]],
    *,
    detail: str,
) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for coordinate in coordinates:
        if len(coordinate) < 2:
            continue
        longitude = float(coordinate[0])
        latitude = float(coordinate[1])
        points.append((latitude, longitude))

    max_points = DETAIL_POINT_LIMITS.get(detail, DETAIL_POINT_LIMITS["desktop"])
    if max_points is None or len(points) <= max_points:
        return points

    step = max(1, len(points) // max_points)
    simplified = points[::step]
    if simplified[-1] != points[-1]:
        simplified.append(points[-1])
    return simplified
