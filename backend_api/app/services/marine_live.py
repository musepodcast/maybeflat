from __future__ import annotations

import json
import math
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from functools import lru_cache
from urllib.error import HTTPError, URLError

from app.schemas.map_models import (
    WeatherOverlaySnapshotResponse,
    WeatherOverlayValueResponse,
    WindSnapshotResponse,
    WindVectorResponse,
)

_MARINE_API_BASE = "https://marine-api.open-meteo.com/v1/marine"
_MAX_PAST_DAYS = 92
_MAX_FUTURE_DAYS = 8
_WAVE_GRAVITY_MPS2 = 9.80665
_MARINE_LOCALITY_THRESHOLD_DEGREES = 7.5


class LiveMarineDataError(RuntimeError):
    pass


@dataclass(frozen=True)
class _MarineModeConfig:
    hourly_variables: tuple[str, ...]
    label: str
    source: str


@dataclass(frozen=True)
class _MarineOverlayConfig:
    hourly_variables: tuple[str, ...]
    label: str
    unit_label: str
    source: str


_MARINE_MODE_CONFIGS: dict[str, _MarineModeConfig] = {
    "currents": _MarineModeConfig(
        hourly_variables=("ocean_current_velocity", "ocean_current_direction"),
        label="Currents",
        source="Open-Meteo Marine API (best match ocean current model)",
    ),
    "waves": _MarineModeConfig(
        hourly_variables=("wave_height", "wave_direction", "wave_period"),
        label="Waves",
        source="Open-Meteo Marine API (best match wave model)",
    ),
}

_OCEAN_OVERLAY_CONFIGS: dict[str, _MarineOverlayConfig] = {
    "currents": _MarineOverlayConfig(
        hourly_variables=("ocean_current_velocity", "ocean_current_direction"),
        label="Currents",
        unit_label="m/s",
        source="Open-Meteo Marine API (best match ocean current model)",
    ),
    "waves": _MarineOverlayConfig(
        hourly_variables=("wave_height", "wave_direction", "wave_period"),
        label="Waves",
        unit_label="m/s",
        source="Open-Meteo Marine API (derived wave propagation speed)",
    ),
    "htsgw": _MarineOverlayConfig(
        hourly_variables=("wave_height",),
        label="HTSGW",
        unit_label="m",
        source="Open-Meteo Marine API (significant wave height)",
    ),
    "sst": _MarineOverlayConfig(
        hourly_variables=("sea_surface_temperature",),
        label="SST",
        unit_label="C",
        source="Open-Meteo Marine API (sea surface temperature)",
    ),
    "ssta": _MarineOverlayConfig(
        hourly_variables=("sea_surface_temperature",),
        label="SSTA",
        unit_label="C",
        source="Derived from Open-Meteo Marine API live SST against a seasonal ocean climatology",
    ),
    "baa": _MarineOverlayConfig(
        hourly_variables=("sea_surface_temperature",),
        label="BAA",
        unit_label="index",
        source="Derived coral bleaching alert proxy from Open-Meteo Marine API live SST",
    ),
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


def _round_to_hour(timestamp_utc: datetime) -> datetime:
    rounded = timestamp_utc.astimezone(UTC).replace(
        minute=0,
        second=0,
        microsecond=0,
    )
    if timestamp_utc.minute >= 30:
        rounded += timedelta(hours=1)
    return rounded


def _validate_supported_time_range(timestamp_utc: datetime) -> None:
    now_utc = datetime.now(UTC)
    if timestamp_utc < now_utc - timedelta(days=_MAX_PAST_DAYS):
        raise ValueError(
            f"Live ocean datasets are only available for roughly the last {_MAX_PAST_DAYS} days."
        )
    if timestamp_utc > now_utc + timedelta(days=_MAX_FUTURE_DAYS):
        raise ValueError(
            f"Live ocean forecast datasets are only available for roughly the next {_MAX_FUTURE_DAYS} days."
        )


def _chunked_points(
    points: list[tuple[float, float]],
    chunk_size: int = 64,
) -> list[list[tuple[float, float]]]:
    return [
        points[index : index + chunk_size]
        for index in range(0, len(points), chunk_size)
    ]


def _longitude_distance_degrees(from_longitude: float, to_longitude: float) -> float:
    wrapped = (to_longitude - from_longitude + 540.0) % 360.0 - 180.0
    return abs(wrapped)


def _component_vector_from_heading(
    speed_mps: float,
    direction_degrees: float,
) -> tuple[float, float]:
    radians = math.radians(direction_degrees)
    u_mps = speed_mps * math.sin(radians)
    v_mps = speed_mps * math.cos(radians)
    return (u_mps, v_mps)


def _wave_speed_mps(height_m: float, period_s: float) -> float:
    if period_s <= 0:
        return 0.0
    base_speed = (_WAVE_GRAVITY_MPS2 * period_s) / (2.0 * math.pi)
    height_factor = max(0.45, min(1.35, 0.7 + (height_m * 0.22)))
    return base_speed * height_factor


def _sst_climatology_c(latitude: float, day_of_year: int) -> float:
    latitude_abs = abs(latitude)
    hemisphere_shift = 0.0 if latitude >= 0 else math.pi
    seasonal_cycle = math.cos(
        ((2.0 * math.pi * (day_of_year - 32)) / 365.2425) - hemisphere_shift
    )
    base_temperature = 29.5 - (0.52 * latitude_abs)
    seasonal_amplitude = min(5.5, 0.5 + (latitude_abs * 0.07))
    return max(
        -1.8,
        min(31.5, base_temperature + (seasonal_amplitude * seasonal_cycle)),
    )


def _bleaching_alert_area_index(latitude: float, sst_c: float, ssta_c: float) -> int:
    if abs(latitude) > 35.0 or sst_c < 26.0 or ssta_c < 0.25:
        return 0
    if ssta_c < 0.5:
        return 1
    if ssta_c < 1.0:
        return 2
    if ssta_c < 1.5:
        return 3
    if ssta_c < 2.0:
        return 4
    if ssta_c < 2.5:
        return 5
    if ssta_c < 3.0:
        return 6
    return 7


def _find_requested_hour_index(payload: dict[str, object], target_epoch: int) -> int:
    hourly = payload.get("hourly")
    if not isinstance(hourly, dict):
        raise LiveMarineDataError("Marine API response is missing hourly data.")
    times = hourly.get("time")
    if not isinstance(times, list) or not times:
        raise LiveMarineDataError("Marine API response is missing hourly timestamps.")
    for index, raw_value in enumerate(times):
        if isinstance(raw_value, (int, float)) and int(raw_value) == target_epoch:
            return index
    return 0


def _payloads_from_response(payload: object) -> list[dict[str, object]]:
    if isinstance(payload, dict):
        return [payload]
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    raise LiveMarineDataError("Marine API returned an unsupported response shape.")


def _extract_used_coordinate(
    payload: dict[str, object],
    key: str,
    requested_value: float,
) -> float:
    raw_value = payload.get(key)
    if isinstance(raw_value, (int, float)):
        return float(raw_value)
    return requested_value


def _is_local_marine_match(
    requested_latitude: float,
    requested_longitude: float,
    used_latitude: float,
    used_longitude: float,
) -> bool:
    latitude_distance = abs(used_latitude - requested_latitude)
    longitude_distance = _longitude_distance_degrees(
        requested_longitude,
        used_longitude,
    )
    return (
        math.sqrt(
            (latitude_distance * latitude_distance)
            + (longitude_distance * longitude_distance)
        )
        <= _MARINE_LOCALITY_THRESHOLD_DEGREES
    )


def _zero_vector(latitude: float, longitude: float) -> WindVectorResponse:
    return WindVectorResponse(
        latitude=round(latitude, 6),
        longitude=round(longitude, 6),
        u_mps=0.0,
        v_mps=0.0,
        speed_mps=0.0,
    )


def _marine_latitudes(grid_step_degrees: int) -> list[float]:
    return [
        float(latitude)
        for latitude in range(-85, 86, grid_step_degrees)
        if latitude != -85
    ]


def _empty_marine_payload(
    *,
    latitude: float,
    longitude: float,
    hourly_variables: tuple[str, ...],
    target_epoch: int,
) -> dict[str, object]:
    return {
        "latitude": latitude,
        "longitude": longitude,
        "hourly": {
            "time": [target_epoch],
            **{variable: [None] for variable in hourly_variables},
        },
    }


def _fetch_payload_chunk(
    *,
    hourly_variables: tuple[str, ...],
    target_time_utc: datetime,
    points: list[tuple[float, float]],
) -> list[dict[str, object]]:
    query = urllib.parse.urlencode(
        {
            "latitude": ",".join(f"{latitude:.4f}" for latitude, _ in points),
            "longitude": ",".join(f"{longitude:.4f}" for _, longitude in points),
            "hourly": ",".join(hourly_variables),
            "start_hour": target_time_utc.strftime("%Y-%m-%dT%H:%M"),
            "end_hour": target_time_utc.strftime("%Y-%m-%dT%H:%M"),
            "timezone": "GMT",
            "timeformat": "unixtime",
            "cell_selection": "sea",
            "length_unit": "metric",
        }
    )
    request = urllib.request.Request(
        f"{_MARINE_API_BASE}?{query}",
        headers={
            "User-Agent": "Maybeflat/1.0 (+https://maybeflat.com)",
            "Accept": "application/json",
        },
    )
    last_network_error: URLError | None = None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                payload = json.loads(response.read().decode("utf-8"))
            break
        except HTTPError as exc:
            error_body = exc.read().decode("utf-8", errors="replace")
            if exc.code == 429:
                if attempt == 2:
                    raise LiveMarineDataError(
                        "Live marine dataset provider rate-limited the request."
                    ) from exc
                retry_after_header = exc.headers.get("Retry-After", "").strip()
                retry_after_seconds = 1.5 * (attempt + 1)
                if retry_after_header.isdigit():
                    retry_after_seconds = max(
                        retry_after_seconds,
                        float(retry_after_header),
                    )
                time.sleep(retry_after_seconds)
                continue
            if exc.code == 400 and "No data is available for this location" in error_body:
                if len(points) == 1:
                    latitude, longitude = points[0]
                    return [
                        _empty_marine_payload(
                            latitude=latitude,
                            longitude=longitude,
                            hourly_variables=hourly_variables,
                            target_epoch=int(target_time_utc.timestamp()),
                        )
                    ]

                midpoint = len(points) // 2
                return _fetch_payload_chunk(
                    hourly_variables=hourly_variables,
                    target_time_utc=target_time_utc,
                    points=points[:midpoint],
                ) + _fetch_payload_chunk(
                    hourly_variables=hourly_variables,
                    target_time_utc=target_time_utc,
                    points=points[midpoint:],
                )
            raise LiveMarineDataError(
                f"Live marine dataset request failed with HTTP {exc.code}."
            ) from exc
        except URLError as exc:
            last_network_error = exc
            if attempt == 2:
                raise LiveMarineDataError(
                    "Live marine dataset request could not reach the provider."
                ) from exc
            time.sleep(0.35 * (attempt + 1))
    else:
        raise LiveMarineDataError(
            "Live marine dataset request could not reach the provider."
        ) from last_network_error

    payloads = _payloads_from_response(payload)
    if len(payloads) != len(points):
        raise LiveMarineDataError(
            "Live marine dataset returned an unexpected number of locations."
        )

    return payloads


def _fetch_chunk(
    *,
    mode: str,
    target_time_utc: datetime,
    points: list[tuple[float, float]],
) -> list[WindVectorResponse]:
    config = _MARINE_MODE_CONFIGS[mode]
    payloads = _fetch_payload_chunk(
        hourly_variables=config.hourly_variables,
        target_time_utc=target_time_utc,
        points=points,
    )

    target_epoch = int(target_time_utc.timestamp())
    vectors: list[WindVectorResponse] = []

    for index, item in enumerate(payloads):
        requested_latitude, requested_longitude = points[index]
        latitude = requested_latitude
        longitude = requested_longitude
        hourly = item.get("hourly")
        if not isinstance(hourly, dict):
            raise LiveMarineDataError("Marine API response is missing hourly values.")
        hour_index = _find_requested_hour_index(item, target_epoch)
        used_latitude = _extract_used_coordinate(item, "latitude", requested_latitude)
        used_longitude = _extract_used_coordinate(
            item,
            "longitude",
            requested_longitude,
        )
        has_local_marine_match = _is_local_marine_match(
            requested_latitude,
            requested_longitude,
            used_latitude,
            used_longitude,
        )

        if mode == "currents":
            velocity_values = hourly.get("ocean_current_velocity")
            direction_values = hourly.get("ocean_current_direction")
            if not isinstance(velocity_values, list) or not isinstance(
                direction_values, list
            ):
                raise LiveMarineDataError("Marine API currents response is incomplete.")
            raw_speed = velocity_values[hour_index]
            raw_direction = direction_values[hour_index]
            if raw_speed is None or raw_direction is None or not has_local_marine_match:
                speed_mps = 0.0
                direction_degrees = 0.0
            else:
                speed_mps = max(0.0, float(raw_speed)) / 3.6
                direction_degrees = float(raw_direction)
        else:
            height_values = hourly.get("wave_height")
            direction_values = hourly.get("wave_direction")
            period_values = hourly.get("wave_period")
            if (
                not isinstance(height_values, list)
                or not isinstance(direction_values, list)
                or not isinstance(period_values, list)
            ):
                raise LiveMarineDataError("Marine API wave response is incomplete.")
            raw_height = height_values[hour_index]
            raw_direction = direction_values[hour_index]
            raw_period = period_values[hour_index]
            if (
                raw_height is None
                or raw_direction is None
                or raw_period is None
                or not has_local_marine_match
            ):
                speed_mps = 0.0
                direction_degrees = 0.0
            else:
                wave_height_m = max(0.0, float(raw_height))
                wave_period_s = max(0.0, float(raw_period))
                wave_from_direction_degrees = float(raw_direction)
                direction_degrees = (wave_from_direction_degrees + 180.0) % 360.0
                speed_mps = _wave_speed_mps(wave_height_m, wave_period_s)

        u_mps, v_mps = _component_vector_from_heading(speed_mps, direction_degrees)
        vectors.append(
            WindVectorResponse(
                latitude=round(latitude, 6),
                longitude=round(longitude, 6),
                u_mps=round(u_mps, 3),
                v_mps=round(v_mps, 3),
                speed_mps=round(speed_mps, 3),
            )
        )

    return vectors


@lru_cache(maxsize=96)
def _get_live_marine_animation_snapshot_cached(
    mode: str,
    effective_timestamp_utc_iso: str,
    grid_step_degrees: int,
) -> WindSnapshotResponse:
    config = _MARINE_MODE_CONFIGS.get(mode)
    if config is None:
        raise ValueError("Unsupported live marine animation mode.")

    effective_timestamp_utc = datetime.fromisoformat(
        effective_timestamp_utc_iso.replace("Z", "+00:00")
    ).astimezone(UTC)
    _validate_supported_time_range(effective_timestamp_utc)

    points = [
        (latitude, float(longitude))
        for latitude in _marine_latitudes(grid_step_degrees)
        for longitude in range(-180, 180, grid_step_degrees)
    ]

    vectors: list[WindVectorResponse] = []
    for chunk in _chunked_points(points):
        vectors.extend(
            _fetch_chunk(
                mode=mode,
                target_time_utc=effective_timestamp_utc,
                points=chunk,
            )
        )

    min_speed = min((vector.speed_mps for vector in vectors), default=0.0)
    max_speed = max((vector.speed_mps for vector in vectors), default=0.0)

    return WindSnapshotResponse(
        timestamp_utc=effective_timestamp_utc.isoformat().replace("+00:00", "Z"),
        source=config.source,
        level="surface",
        grid_step_degrees=grid_step_degrees,
        min_speed_mps=round(min_speed, 3),
        max_speed_mps=round(max_speed, 3),
        vectors=vectors,
    )


def get_live_marine_animation_snapshot(
    *,
    mode: str,
    timestamp_utc: str | None = None,
    grid_step_degrees: int = 15,
) -> WindSnapshotResponse:
    effective_timestamp_utc = _round_to_hour(_parse_timestamp_utc(timestamp_utc))
    return _get_live_marine_animation_snapshot_cached(
        mode,
        effective_timestamp_utc.isoformat().replace("+00:00", "Z"),
        grid_step_degrees,
    )


def _overlay_value_from_payload(
    *,
    overlay: str,
    payload: dict[str, object],
    target_epoch: int,
    requested_latitude: float,
    requested_longitude: float,
    target_time_utc: datetime,
) -> float:
    hourly = payload.get("hourly")
    if not isinstance(hourly, dict):
        raise LiveMarineDataError("Marine API response is missing hourly values.")
    hour_index = _find_requested_hour_index(payload, target_epoch)
    used_latitude = _extract_used_coordinate(payload, "latitude", requested_latitude)
    used_longitude = _extract_used_coordinate(
        payload,
        "longitude",
        requested_longitude,
    )
    has_local_marine_match = _is_local_marine_match(
        requested_latitude,
        requested_longitude,
        used_latitude,
        used_longitude,
    )
    if not has_local_marine_match:
        return 0.0

    if overlay == "currents":
        values = hourly.get("ocean_current_velocity")
        if not isinstance(values, list):
            raise LiveMarineDataError("Marine API currents overlay response is incomplete.")
        raw_value = values[hour_index]
        return 0.0 if raw_value is None else max(0.0, float(raw_value)) / 3.6

    if overlay == "waves":
        height_values = hourly.get("wave_height")
        period_values = hourly.get("wave_period")
        if not isinstance(height_values, list) or not isinstance(period_values, list):
            raise LiveMarineDataError("Marine API waves overlay response is incomplete.")
        raw_height = height_values[hour_index]
        raw_period = period_values[hour_index]
        if raw_height is None or raw_period is None:
            return 0.0
        return _wave_speed_mps(
            max(0.0, float(raw_height)),
            max(0.0, float(raw_period)),
        )

    if overlay == "htsgw":
        values = hourly.get("wave_height")
        if not isinstance(values, list):
            raise LiveMarineDataError("Marine API HTSGW response is incomplete.")
        raw_value = values[hour_index]
        return 0.0 if raw_value is None else max(0.0, float(raw_value))

    if overlay in {"sst", "ssta", "baa"}:
        values = hourly.get("sea_surface_temperature")
        if not isinstance(values, list):
            raise LiveMarineDataError("Marine API SST response is incomplete.")
        raw_sst = values[hour_index]
        if raw_sst is None:
            return 0.0
        sst_c = float(raw_sst)
        if overlay == "sst":
            return sst_c
        day_of_year = target_time_utc.timetuple().tm_yday
        ssta_c = sst_c - _sst_climatology_c(requested_latitude, day_of_year)
        if overlay == "ssta":
            return ssta_c
        return float(
            _bleaching_alert_area_index(
                requested_latitude,
                sst_c,
                ssta_c,
            )
        )

    raise ValueError("Unsupported live ocean overlay.")


@lru_cache(maxsize=96)
def _get_live_ocean_overlay_snapshot_cached(
    overlay: str,
    effective_timestamp_utc_iso: str,
    grid_step_degrees: int,
) -> WeatherOverlaySnapshotResponse:
    config = _OCEAN_OVERLAY_CONFIGS.get(overlay)
    if config is None:
        raise ValueError("Unsupported live ocean overlay.")

    effective_timestamp_utc = datetime.fromisoformat(
        effective_timestamp_utc_iso.replace("Z", "+00:00")
    ).astimezone(UTC)
    _validate_supported_time_range(effective_timestamp_utc)
    target_epoch = int(effective_timestamp_utc.timestamp())

    points = [
        (latitude, float(longitude))
        for latitude in _marine_latitudes(grid_step_degrees)
        for longitude in range(-180, 180, grid_step_degrees)
    ]

    values: list[WeatherOverlayValueResponse] = []
    min_value = math.inf
    max_value = -math.inf

    for chunk in _chunked_points(points):
        payloads = _fetch_payload_chunk(
            hourly_variables=config.hourly_variables,
            target_time_utc=effective_timestamp_utc,
            points=chunk,
        )
        for index, payload in enumerate(payloads):
            latitude, longitude = chunk[index]
            value = _overlay_value_from_payload(
                overlay=overlay,
                payload=payload,
                target_epoch=target_epoch,
                requested_latitude=latitude,
                requested_longitude=longitude,
                target_time_utc=effective_timestamp_utc,
            )
            min_value = min(min_value, value)
            max_value = max(max_value, value)
            values.append(
                WeatherOverlayValueResponse(
                    latitude=round(latitude, 6),
                    longitude=round(longitude, 6),
                    value=round(value, 3),
                )
            )

    if not values:
        min_value = 0.0
        max_value = 1.0

    return WeatherOverlaySnapshotResponse(
        timestamp_utc=effective_timestamp_utc.isoformat().replace("+00:00", "Z"),
        source=config.source,
        overlay=overlay,
        overlay_label=config.label,
        unit_label=config.unit_label,
        level="surface",
        grid_step_degrees=grid_step_degrees,
        min_value=round(min_value, 3),
        max_value=round(max_value, 3),
        values=values,
    )


def get_live_ocean_overlay_snapshot(
    *,
    overlay: str,
    timestamp_utc: str | None = None,
    grid_step_degrees: int = 15,
) -> WeatherOverlaySnapshotResponse:
    effective_timestamp_utc = _round_to_hour(_parse_timestamp_utc(timestamp_utc))
    return _get_live_ocean_overlay_snapshot_cached(
        overlay,
        effective_timestamp_utc.isoformat().replace("+00:00", "Z"),
        grid_step_degrees,
    )
