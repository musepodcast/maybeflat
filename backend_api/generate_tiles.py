from __future__ import annotations

import argparse
import sys
from pathlib import Path


def _bootstrap_repo() -> None:
    backend_root = Path(__file__).resolve().parent
    if str(backend_root) not in sys.path:
        sys.path.insert(0, str(backend_root))


_bootstrap_repo()

from app.services.tile_renderer import EDGE_MODES, MAX_TILE_ZOOM, render_tile_png


def _parse_edge_modes(raw_value: str) -> list[str]:
    requested = [value.strip() for value in raw_value.split(",") if value.strip()]
    if not requested:
        return list(EDGE_MODES)

    invalid = [value for value in requested if value not in EDGE_MODES]
    if invalid:
        raise ValueError(
            f"Unsupported edge modes: {', '.join(invalid)}. Expected one of: {', '.join(EDGE_MODES)}",
        )
    return requested


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Pre-render the shared Maybeflat raster tile pyramid.",
    )
    parser.add_argument(
        "--max-zoom",
        type=int,
        default=MAX_TILE_ZOOM,
        help=f"Highest z level to generate (0-{MAX_TILE_ZOOM}). Default: {MAX_TILE_ZOOM}.",
    )
    parser.add_argument(
        "--edge-modes",
        default="coastline,country,both",
        help="Comma-separated edge modes to render.",
    )
    args = parser.parse_args()

    if args.max_zoom < 0 or args.max_zoom > MAX_TILE_ZOOM:
        raise ValueError(f"--max-zoom must be between 0 and {MAX_TILE_ZOOM}.")

    edge_modes = _parse_edge_modes(args.edge_modes)
    total_tiles = sum((1 << zoom) ** 2 for zoom in range(args.max_zoom + 1))
    total_jobs = total_tiles * len(edge_modes)
    completed = 0

    for edge_mode in edge_modes:
        for zoom in range(args.max_zoom + 1):
            tile_count = 1 << zoom
            for x in range(tile_count):
                for y in range(tile_count):
                    render_tile_png(
                        edge_mode=edge_mode,
                        z=zoom,
                        x=x,
                        y=y,
                    )
                    completed += 1
                    if completed == 1 or completed % 250 == 0 or completed == total_jobs:
                        print(
                            f"[{completed}/{total_jobs}] rendered {edge_mode} z{zoom}/{x}/{y}",
                            flush=True,
                        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
