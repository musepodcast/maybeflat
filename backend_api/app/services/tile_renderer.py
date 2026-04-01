from __future__ import annotations

from functools import lru_cache
from io import BytesIO
from typing import TypeAlias

from PIL import Image, ImageChops, ImageDraw

from app.schemas.map_models import MapSceneResponse, MapShapeResponse, TileManifestResponse
from app.services.flat_world import build_scene

TILE_SIZE = 256
MAX_TILE_ZOOM = 6
WORLD_HALF_EXTENT = 1 / 0.94
WORLD_MIN = -WORLD_HALF_EXTENT
WORLD_MAX = WORLD_HALF_EXTENT
DETAIL_LEVELS = ["mobile", "desktop", "full"]
EDGE_MODES = ["coastline", "country", "both"]
SUPER_SAMPLE_SCALE = 2
DEFAULT_WARM_EDGE_MODE = "coastline"
DEFAULT_WARM_SCENE_DETAILS = ("mobile", "desktop", "full")
DEFAULT_WARM_TILE_DETAILS = ("mobile", "desktop")
DEFAULT_WARM_MAX_ZOOM = 2
ShapeBounds: TypeAlias = tuple[float, float, float, float]
IndexedShape: TypeAlias = tuple[MapShapeResponse, ShapeBounds]


def build_tile_manifest() -> TileManifestResponse:
    return TileManifestResponse(
        tile_size=TILE_SIZE,
        max_zoom=MAX_TILE_ZOOM,
        world_min=round(WORLD_MIN, 6),
        world_max=round(WORLD_MAX, 6),
        detail_levels=DETAIL_LEVELS,
        edge_modes=EDGE_MODES,
        url_template="/map/tiles/{detail}/{edge_mode}/{z}/{x}/{y}.png",
    )


def render_tile_png(
    *,
    detail: str,
    edge_mode: str,
    z: int,
    x: int,
    y: int,
) -> bytes:
    if detail not in DETAIL_LEVELS:
        raise ValueError(f"Unsupported tile detail: {detail}")
    if edge_mode not in EDGE_MODES:
        raise ValueError(f"Unsupported edge mode: {edge_mode}")
    if z < 0 or z > MAX_TILE_ZOOM:
        raise ValueError(f"Unsupported tile zoom: {z}")

    max_index = (1 << z) - 1
    if x < 0 or x > max_index or y < 0 or y > max_index:
        raise ValueError("Tile coordinate out of range")

    return _render_tile_png_cached(detail, edge_mode, z, x, y)


def warm_default_cache() -> None:
    for detail in DEFAULT_WARM_SCENE_DETAILS:
        _get_scene(detail)
        _get_indexed_scene(detail)

    for detail in DEFAULT_WARM_TILE_DETAILS:
        for zoom in range(DEFAULT_WARM_MAX_ZOOM + 1):
            for x, y in _ordered_tile_coordinates(zoom):
                _render_tile_png_cached(detail, DEFAULT_WARM_EDGE_MODE, zoom, x, y)


@lru_cache(maxsize=8)
def _get_scene(detail: str) -> MapSceneResponse:
    return build_scene(detail, include_state_boundaries=False)


@lru_cache(maxsize=8)
def _get_indexed_scene(
    detail: str,
) -> tuple[
    MapSceneResponse,
    tuple[IndexedShape, ...],
    tuple[IndexedShape, ...],
    tuple[IndexedShape, ...],
    tuple[IndexedShape, ...],
]:
    scene = _get_scene(detail)
    land_shapes: list[IndexedShape] = []
    boundary_shapes: list[IndexedShape] = []
    state_boundary_shapes: list[IndexedShape] = []
    timezone_shapes: list[IndexedShape] = []
    for shape in scene.shapes:
        indexed_shape = (shape, _shape_bounds(shape))
        if shape.role == "boundary":
            boundary_shapes.append(indexed_shape)
        elif shape.role == "state_boundary":
            state_boundary_shapes.append(indexed_shape)
        elif shape.role == "timezone":
            timezone_shapes.append(indexed_shape)
        else:
            land_shapes.append(indexed_shape)
    return (
        scene,
        tuple(land_shapes),
        tuple(boundary_shapes),
        tuple(state_boundary_shapes),
        tuple(timezone_shapes),
    )


@lru_cache(maxsize=1024)
def _render_tile_png_cached(
    detail: str,
    edge_mode: str,
    z: int,
    x: int,
    y: int,
) -> bytes:
    tile_pixels = TILE_SIZE * SUPER_SAMPLE_SCALE
    tile_image = Image.new("RGBA", (tile_pixels, tile_pixels), (0, 0, 0, 0))
    draw = ImageDraw.Draw(tile_image, "RGBA")

    tile_bounds = _tile_bounds(z, x, y)
    _, indexed_land_shapes, indexed_boundary_shapes, _, _ = _get_indexed_scene(detail)
    land_shapes = [
        shape
        for shape, bounds in indexed_land_shapes
        if _bounds_intersect(bounds, tile_bounds)
    ]
    boundary_shapes = [
        shape
        for shape, bounds in indexed_boundary_shapes
        if _bounds_intersect(bounds, tile_bounds)
    ]
    disk_bbox = _project_circle_bbox(tile_bounds, tile_pixels, radius=1.0)
    inner_ocean_bbox = _project_circle_bbox(tile_bounds, tile_pixels, radius=0.85)

    draw.ellipse(disk_bbox, fill=_hex_to_rgba("#96C5C2"))
    draw.ellipse(inner_ocean_bbox, fill=_hex_to_rgba("#96C5C2"))
    draw.ellipse(
        disk_bbox,
        outline=_hex_to_rgba("#DCEFF4"),
        width=max(1, round(3 * SUPER_SAMPLE_SCALE)),
    )

    land_mask = Image.new("L", (tile_pixels, tile_pixels), 0)
    land_mask_draw = ImageDraw.Draw(land_mask)
    for shape in land_shapes:
        _draw_shape_fill_mask(land_mask_draw, shape, tile_bounds, tile_pixels)

    land_fill = Image.new("RGBA", (tile_pixels, tile_pixels), (0, 0, 0, 0))
    land_fill_draw = ImageDraw.Draw(land_fill, "RGBA")
    for shape in land_shapes:
        _draw_shape_fill(land_fill_draw, shape, tile_bounds, tile_pixels)
    tile_image.alpha_composite(Image.composite(land_fill, Image.new("RGBA", land_fill.size), land_mask))

    if edge_mode in {"country", "both", "coastline"}:
        boundary_layer = Image.new("RGBA", (tile_pixels, tile_pixels), (0, 0, 0, 0))
        boundary_draw = ImageDraw.Draw(boundary_layer, "RGBA")
        for shape in boundary_shapes:
            _draw_shape_strokes(
                boundary_draw,
                shape,
                tile_bounds,
                tile_pixels,
                width=max(1, round(1.2 * SUPER_SAMPLE_SCALE)),
                alpha=132 if detail != "mobile" else 110,
            )
        if edge_mode == "coastline":
            boundary_alpha = boundary_layer.getchannel("A")
            clipped_alpha = ImageChops.multiply(boundary_alpha, land_mask)
            boundary_layer.putalpha(clipped_alpha)
        tile_image.alpha_composite(boundary_layer)

    if edge_mode in {"coastline", "both"}:
        coast_layer = Image.new("RGBA", (tile_pixels, tile_pixels), (0, 0, 0, 0))
        coast_draw = ImageDraw.Draw(coast_layer, "RGBA")
        for shape in land_shapes:
            width = (
                max(2, round(3.4 * SUPER_SAMPLE_SCALE))
                if shape.name == "Antarctica Rim"
                else max(1, round(0.75 * SUPER_SAMPLE_SCALE))
            )
            _draw_shape_strokes(
                coast_draw,
                shape,
                tile_bounds,
                tile_pixels,
                width=width,
                alpha=255,
            )
        tile_image.alpha_composite(coast_layer)

    if SUPER_SAMPLE_SCALE > 1:
        tile_image = tile_image.resize((TILE_SIZE, TILE_SIZE), Image.Resampling.LANCZOS)

    buffer = BytesIO()
    tile_image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def _tile_bounds(z: int, x: int, y: int) -> tuple[float, float, float, float]:
    tile_count = 1 << z
    tile_world_span = (WORLD_MAX - WORLD_MIN) / tile_count
    left = WORLD_MIN + x * tile_world_span
    top = WORLD_MIN + y * tile_world_span
    return left, top, left + tile_world_span, top + tile_world_span


def _project_circle_bbox(
    tile_bounds: tuple[float, float, float, float],
    tile_pixels: int,
    *,
    radius: float,
) -> tuple[float, float, float, float]:
    left, top = _project_xy(-radius, -radius, tile_bounds, tile_pixels)
    right, bottom = _project_xy(radius, radius, tile_bounds, tile_pixels)
    return left, top, right, bottom


def _ordered_tile_coordinates(z: int) -> list[tuple[int, int]]:
    tile_count = 1 << z
    center = (tile_count - 1) / 2
    coordinates = [
        (x, y)
        for x in range(tile_count)
        for y in range(tile_count)
    ]
    coordinates.sort(
        key=lambda item: (
            (item[0] - center) ** 2 + (item[1] - center) ** 2,
            item[1],
            item[0],
        )
    )
    return coordinates


def _shape_bounds(shape: MapShapeResponse) -> ShapeBounds:
    min_x = float("inf")
    min_y = float("inf")
    max_x = float("-inf")
    max_y = float("-inf")
    for ring in shape.rings:
        for point in ring.points:
            min_x = min(min_x, point.x)
            min_y = min(min_y, point.y)
            max_x = max(max_x, point.x)
            max_y = max(max_y, point.y)
    return min_x, min_y, max_x, max_y


def _bounds_intersect(
    shape_bounds: ShapeBounds,
    tile_bounds: tuple[float, float, float, float],
) -> bool:
    shape_left, shape_top, shape_right, shape_bottom = shape_bounds
    tile_left, tile_top, tile_right, tile_bottom = tile_bounds
    return not (
        shape_right < tile_left
        or shape_left > tile_right
        or shape_bottom < tile_top
        or shape_top > tile_bottom
    )


def _draw_shape_fill_mask(
    draw: ImageDraw.ImageDraw,
    shape: MapShapeResponse,
    tile_bounds: tuple[float, float, float, float],
    tile_pixels: int,
) -> None:
    if not shape.rings:
        return

    for ring_index, ring in enumerate(shape.rings):
        if not ring.closed or len(ring.points) < 3:
            continue
        projected = _project_ring(ring.points, tile_bounds, tile_pixels)
        if len(projected) < 3:
            continue
        draw.polygon(projected, fill=255 if ring_index == 0 else 0)


def _draw_shape_fill(
    draw: ImageDraw.ImageDraw,
    shape: MapShapeResponse,
    tile_bounds: tuple[float, float, float, float],
    tile_pixels: int,
) -> None:
    if not shape.rings:
        return
    projected = _project_ring(shape.rings[0].points, tile_bounds, tile_pixels)
    if len(projected) < 3:
        return
    draw.polygon(projected, fill=_hex_to_rgba(shape.fill))


def _draw_shape_strokes(
    draw: ImageDraw.ImageDraw,
    shape: MapShapeResponse,
    tile_bounds: tuple[float, float, float, float],
    tile_pixels: int,
    *,
    width: int,
    alpha: int,
) -> None:
    stroke_color = _hex_to_rgba(shape.stroke, alpha=alpha)
    for ring in shape.rings:
        projected = _project_ring(ring.points, tile_bounds, tile_pixels)
        if len(projected) < 2:
            continue
        points = projected + [projected[0]] if ring.closed else projected
        draw.line(points, fill=stroke_color, width=width, joint="curve")


def _project_ring(
    points,
    tile_bounds: tuple[float, float, float, float],
    tile_pixels: int,
) -> list[tuple[float, float]]:
    projected: list[tuple[float, float]] = []
    for point in points:
        px, py = _project_xy(point.x, point.y, tile_bounds, tile_pixels)
        projected.append((px, py))
    return projected


def _project_xy(
    x: float,
    y: float,
    tile_bounds: tuple[float, float, float, float],
    tile_pixels: int,
) -> tuple[float, float]:
    left, top, right, bottom = tile_bounds
    world_width = right - left
    world_height = bottom - top
    px = ((x - left) / world_width) * tile_pixels
    py = ((y - top) / world_height) * tile_pixels
    return px, py


def _hex_to_rgba(value: str, *, alpha: int | None = None) -> tuple[int, int, int, int]:
    normalized = value.replace("#", "")
    if len(normalized) == 6:
        rgba = normalized + "FF"
    elif len(normalized) == 8:
        rgba = normalized[2:] + normalized[:2]
    else:
        raise ValueError(f"Unsupported color value: {value}")

    red = int(rgba[0:2], 16)
    green = int(rgba[2:4], 16)
    blue = int(rgba[4:6], 16)
    base_alpha = int(rgba[6:8], 16)
    return red, green, blue, base_alpha if alpha is None else alpha
