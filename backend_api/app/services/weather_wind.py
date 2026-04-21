from __future__ import annotations

import math
from datetime import UTC, datetime
from typing import TypedDict

from app.schemas.map_models import WindSnapshotResponse, WindVectorResponse
from app.services.marine_live import get_live_marine_animation_snapshot


class _WindLevelProfile(TypedDict):
    label: str
    altitude_km: float
    trade_strength: float
    trade_center: float
    trade_width: float
    westerly_strength: float
    westerly_center: float
    westerly_width: float
    polar_strength: float
    polar_center: float
    polar_width: float
    zonal_boost: float
    meridional_boost: float
    wave_scale: float
    phase_scale: float


class _AnimationModeMetadata(TypedDict):
    label: str
    source_label: str


_WIND_LEVELS: dict[str, _WindLevelProfile] = {
    "surface": {
        "label": "Surface",
        "altitude_km": 0.0,
        "trade_strength": -8.5,
        "trade_center": 18.0,
        "trade_width": 26.0,
        "westerly_strength": 13.0,
        "westerly_center": 47.0,
        "westerly_width": 18.0,
        "polar_strength": -5.5,
        "polar_center": 74.0,
        "polar_width": 14.0,
        "zonal_boost": 1.0,
        "meridional_boost": 1.0,
        "wave_scale": 1.0,
        "phase_scale": 1.0,
    },
    "1000": {
        "label": "1000 hPa",
        "altitude_km": 0.11,
        "trade_strength": -8.0,
        "trade_center": 19.0,
        "trade_width": 25.0,
        "westerly_strength": 12.0,
        "westerly_center": 46.0,
        "westerly_width": 18.0,
        "polar_strength": -5.2,
        "polar_center": 73.0,
        "polar_width": 14.0,
        "zonal_boost": 0.96,
        "meridional_boost": 1.0,
        "wave_scale": 0.96,
        "phase_scale": 0.94,
    },
    "850": {
        "label": "850 hPa",
        "altitude_km": 1.46,
        "trade_strength": -6.4,
        "trade_center": 18.0,
        "trade_width": 24.0,
        "westerly_strength": 16.0,
        "westerly_center": 44.0,
        "westerly_width": 17.0,
        "polar_strength": -4.0,
        "polar_center": 70.0,
        "polar_width": 13.0,
        "zonal_boost": 1.12,
        "meridional_boost": 0.92,
        "wave_scale": 1.04,
        "phase_scale": 1.02,
    },
    "700": {
        "label": "700 hPa",
        "altitude_km": 3.01,
        "trade_strength": -4.2,
        "trade_center": 17.0,
        "trade_width": 22.0,
        "westerly_strength": 19.5,
        "westerly_center": 42.0,
        "westerly_width": 16.0,
        "polar_strength": -2.4,
        "polar_center": 67.0,
        "polar_width": 12.0,
        "zonal_boost": 1.28,
        "meridional_boost": 0.84,
        "wave_scale": 1.12,
        "phase_scale": 1.08,
    },
    "500": {
        "label": "500 hPa",
        "altitude_km": 5.57,
        "trade_strength": -1.8,
        "trade_center": 16.0,
        "trade_width": 20.0,
        "westerly_strength": 24.0,
        "westerly_center": 40.0,
        "westerly_width": 15.0,
        "polar_strength": 0.8,
        "polar_center": 64.0,
        "polar_width": 12.0,
        "zonal_boost": 1.55,
        "meridional_boost": 0.74,
        "wave_scale": 1.2,
        "phase_scale": 1.14,
    },
    "250": {
        "label": "250 hPa",
        "altitude_km": 10.36,
        "trade_strength": 0.4,
        "trade_center": 14.0,
        "trade_width": 18.0,
        "westerly_strength": 33.0,
        "westerly_center": 34.0,
        "westerly_width": 13.0,
        "polar_strength": 3.5,
        "polar_center": 58.0,
        "polar_width": 11.0,
        "zonal_boost": 2.1,
        "meridional_boost": 0.56,
        "wave_scale": 1.34,
        "phase_scale": 1.2,
    },
    "70": {
        "label": "70 hPa",
        "altitude_km": 18.71,
        "trade_strength": 0.0,
        "trade_center": 12.0,
        "trade_width": 16.0,
        "westerly_strength": 19.0,
        "westerly_center": 52.0,
        "westerly_width": 14.0,
        "polar_strength": 7.2,
        "polar_center": 64.0,
        "polar_width": 10.0,
        "zonal_boost": 1.75,
        "meridional_boost": 0.42,
        "wave_scale": 1.46,
        "phase_scale": 1.28,
    },
    "10": {
        "label": "10 hPa",
        "altitude_km": 31.06,
        "trade_strength": 0.0,
        "trade_center": 10.0,
        "trade_width": 14.0,
        "westerly_strength": 12.5,
        "westerly_center": 58.0,
        "westerly_width": 13.0,
        "polar_strength": 10.2,
        "polar_center": 70.0,
        "polar_width": 9.0,
        "zonal_boost": 1.48,
        "meridional_boost": 0.3,
        "wave_scale": 1.6,
        "phase_scale": 1.36,
    },
}

_ANIMATION_MODES: dict[str, _AnimationModeMetadata] = {
    "wind": {
        "label": "Wind",
        "source_label": "wind field",
    },
    "currents": {
        "label": "Currents",
        "source_label": "surface current field",
    },
    "waves": {
        "label": "Waves",
        "source_label": "wave propagation field",
    },
}


def _parse_timestamp_utc(timestamp_utc: str | None) -> datetime:
    if timestamp_utc is None or not timestamp_utc.strip():
        return datetime.now(UTC)

    normalized = timestamp_utc.strip().replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise ValueError("timestamp_utc must be a valid ISO-8601 timestamp.") from exc

    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def _band_strength(latitude: float, center: float, half_width: float) -> float:
    distance = abs(latitude - center)
    if distance >= half_width:
        return 0.0
    return 1.0 - (distance / half_width)


def _wind_components(
    timestamp_utc: datetime,
    latitude: float,
    longitude: float,
    profile: _WindLevelProfile,
) -> tuple[float, float]:
    latitude_radians = math.radians(latitude)
    longitude_radians = math.radians(longitude)
    hours = timestamp_utc.timestamp() / 3600.0
    phase = hours / (18.0 * profile["phase_scale"])
    wave_scale = profile["wave_scale"]

    trade_strength = _band_strength(
        abs(latitude),
        profile["trade_center"],
        profile["trade_width"],
    )
    westerly_strength = _band_strength(
        abs(latitude),
        profile["westerly_center"],
        profile["westerly_width"],
    )
    polar_strength = _band_strength(
        abs(latitude),
        profile["polar_center"],
        profile["polar_width"],
    )
    equatorial_calm = _band_strength(abs(latitude), 0.0, 10.0)

    u_mps = 0.0
    u_mps += profile["trade_strength"] * trade_strength
    u_mps += profile["westerly_strength"] * westerly_strength
    u_mps += profile["polar_strength"] * polar_strength
    u_mps *= (0.72 + (0.28 * math.cos(latitude_radians) ** 2)) * profile[
        "zonal_boost"
    ]
    u_mps += 3.2 * wave_scale * math.sin((longitude_radians * 2.0) + phase)
    u_mps += 2.1 * wave_scale * math.cos(
        (longitude_radians * 3.0)
        - (latitude_radians * (1.1 + ((wave_scale - 1.0) * 0.25)))
        - (phase * 1.6)
    )
    u_mps += 1.1 * wave_scale * math.sin((hours / 48.0) + (latitude_radians * 4.0))
    if profile["label"] in {"Surface", "1000 hPa", "850 hPa"}:
        u_mps *= 1.0 - (0.28 * equatorial_calm)

    hemisphere = 1.0 if latitude >= 0 else -1.0
    v_mps = 0.0
    v_mps += (
        2.4
        * trade_strength
        * hemisphere
        * math.sin(longitude_radians + phase)
        * profile["meridional_boost"]
    )
    v_mps += (
        1.9
        * westerly_strength
        * hemisphere
        * math.cos((longitude_radians * 1.7) - (phase * 0.6))
        * profile["meridional_boost"]
    )
    v_mps += (
        1.4
        * polar_strength
        * hemisphere
        * math.sin((longitude_radians * 2.6) + (phase * 1.1))
        * profile["meridional_boost"]
    )
    v_mps += (
        1.2
        * wave_scale
        * math.sin(
            (latitude_radians * 2.3)
            + (longitude_radians * 1.4)
            + (phase * 0.75)
        )
        * profile["meridional_boost"]
    )

    return (u_mps, v_mps)


def _current_components(
    timestamp_utc: datetime,
    latitude: float,
    longitude: float,
    profile: _WindLevelProfile,
) -> tuple[float, float]:
    latitude_radians = math.radians(latitude)
    longitude_radians = math.radians(longitude)
    hours = timestamp_utc.timestamp() / 3600.0
    phase = hours / (26.0 * profile["phase_scale"])

    subtropical_gyre = max(
        0.0,
        1.0 - (abs(abs(latitude) - 28.0) / 22.0),
    )
    equatorial_current = max(0.0, 1.0 - (abs(latitude) / 18.0))
    subpolar_current = max(
        0.0,
        1.0 - (abs(abs(latitude) - 56.0) / 16.0),
    )
    hemisphere = 1.0 if latitude >= 0 else -1.0

    gyre_phase = longitude_radians - (phase * 0.55)
    u_mps = 0.0
    u_mps += 1.8 * subtropical_gyre * math.cos(gyre_phase)
    u_mps += 0.95 * equatorial_current * math.sin((longitude_radians * 1.2) + phase)
    u_mps += 0.75 * subpolar_current * math.cos((longitude_radians * 1.35) - (phase * 0.7))
    u_mps += 0.35 * math.sin((latitude_radians * 3.4) + (longitude_radians * 1.8) + (phase * 0.4))

    v_mps = 0.0
    v_mps += -1.45 * subtropical_gyre * hemisphere * math.sin(gyre_phase)
    v_mps += 0.5 * equatorial_current * hemisphere * math.cos((longitude_radians * 0.9) - (phase * 0.65))
    v_mps += 0.55 * subpolar_current * hemisphere * math.sin((longitude_radians * 1.4) + (phase * 0.8))
    v_mps += 0.25 * math.cos((latitude_radians * 2.8) - (longitude_radians * 1.3) + (phase * 0.5))

    depth_factor = math.exp(-profile["altitude_km"] / 12.0)
    return (u_mps * depth_factor, v_mps * depth_factor)


def _wave_components(
    timestamp_utc: datetime,
    latitude: float,
    longitude: float,
    profile: _WindLevelProfile,
) -> tuple[float, float]:
    latitude_radians = math.radians(latitude)
    longitude_radians = math.radians(longitude)
    hours = timestamp_utc.timestamp() / 3600.0
    phase = hours / (9.5 * profile["phase_scale"])
    storm_belt = max(0.0, 1.0 - (abs(abs(latitude) - 42.0) / 20.0))
    trade_belt = max(0.0, 1.0 - (abs(abs(latitude) - 15.0) / 18.0))
    polar_swell = max(0.0, 1.0 - (abs(abs(latitude) - 62.0) / 16.0))
    hemisphere = 1.0 if latitude >= 0 else -1.0

    u_mps = 0.0
    u_mps += 5.1 * storm_belt * math.cos((longitude_radians * 1.55) - phase)
    u_mps += -2.8 * trade_belt * math.cos((longitude_radians * 1.1) + (phase * 0.75))
    u_mps += 1.9 * polar_swell * math.sin((longitude_radians * 1.8) - (phase * 0.55))
    u_mps += 0.95 * math.cos((latitude_radians * 2.4) + (longitude_radians * 2.3) - (phase * 1.2))

    v_mps = 0.0
    v_mps += 1.25 * storm_belt * hemisphere * math.sin((longitude_radians * 1.45) - (phase * 0.9))
    v_mps += 0.85 * trade_belt * hemisphere * math.cos((longitude_radians * 1.35) + (phase * 0.6))
    v_mps += 0.7 * polar_swell * hemisphere * math.sin((longitude_radians * 2.1) - (phase * 0.45))
    v_mps += 0.42 * math.sin((latitude_radians * 3.1) - (longitude_radians * 1.7) + phase)

    altitude_factor = 0.8 + (0.2 * math.exp(-profile["altitude_km"] / 20.0))
    return (u_mps * altitude_factor, v_mps * altitude_factor)


def _animation_components(
    mode: str,
    timestamp_utc: datetime,
    latitude: float,
    longitude: float,
    profile: _WindLevelProfile,
) -> tuple[float, float]:
    if mode == "wind":
        return _wind_components(timestamp_utc, latitude, longitude, profile)
    if mode == "currents":
        return _current_components(timestamp_utc, latitude, longitude, profile)
    if mode == "waves":
        return _wave_components(timestamp_utc, latitude, longitude, profile)
    raise ValueError("Unsupported weather animation mode.")


def get_animation_snapshot(
    *,
    mode: str,
    timestamp_utc: str | None = None,
    level: str = "surface",
    grid_step_degrees: int = 15,
) -> WindSnapshotResponse:
    if mode in {"currents", "waves"}:
        return get_live_marine_animation_snapshot(
            mode=mode,
            timestamp_utc=timestamp_utc,
            grid_step_degrees=grid_step_degrees,
        )

    profile = _WIND_LEVELS.get(level)
    if profile is None:
        raise ValueError("Unsupported wind level.")
    metadata = _ANIMATION_MODES.get(mode)
    if metadata is None:
        raise ValueError("Unsupported weather animation mode.")

    effective_timestamp = _parse_timestamp_utc(timestamp_utc)
    vectors: list[WindVectorResponse] = []
    min_speed = math.inf
    max_speed = 0.0

    for latitude in range(-85, 86, grid_step_degrees):
        for longitude in range(-180, 180, grid_step_degrees):
            u_mps, v_mps = _animation_components(
                mode,
                effective_timestamp,
                float(latitude),
                float(longitude),
                profile,
            )
            speed_mps = math.sqrt((u_mps * u_mps) + (v_mps * v_mps))
            min_speed = min(min_speed, speed_mps)
            max_speed = max(max_speed, speed_mps)
            vectors.append(
                WindVectorResponse(
                    latitude=float(latitude),
                    longitude=float(longitude),
                    u_mps=round(u_mps, 3),
                    v_mps=round(v_mps, 3),
                    speed_mps=round(speed_mps, 3),
                )
            )

    if not vectors:
        min_speed = 0.0

    return WindSnapshotResponse(
        timestamp_utc=effective_timestamp.isoformat().replace("+00:00", "Z"),
        source=f"Preview {metadata['source_label']} (procedural {metadata['label'].lower()} model)",
        level=level,
        grid_step_degrees=grid_step_degrees,
        min_speed_mps=round(min_speed, 3),
        max_speed_mps=round(max_speed, 3),
        vectors=vectors,
    )


def get_wind_snapshot(
    *,
    timestamp_utc: str | None = None,
    level: str = "surface",
    grid_step_degrees: int = 15,
) -> WindSnapshotResponse:
    return get_animation_snapshot(
        mode="wind",
        timestamp_utc=timestamp_utc,
        level=level,
        grid_step_degrees=grid_step_degrees,
    )
