from __future__ import annotations

import math
from datetime import UTC, datetime
from typing import TypedDict

from app.schemas.map_models import (
    WeatherOverlaySnapshotResponse,
    WeatherOverlayValueResponse,
)
from app.services.astronomy import (
    _greenwich_mean_sidereal_degrees,
    _julian_day,
    _subpoint_from_right_ascension,
    _sun_equatorial_position,
)
from app.services.weather_wind import _WIND_LEVELS, _parse_timestamp_utc, _wind_components


class _OverlayMetadata(TypedDict):
    label: str
    unit_label: str


_WEATHER_OVERLAYS: dict[str, _OverlayMetadata] = {
    "wind": {"label": "Wind", "unit_label": "m/s"},
    "temperature": {"label": "Temperature", "unit_label": "C"},
    "relativeHumidity": {"label": "Relative Humidity", "unit_label": "%"},
    "dewPointTemperature": {
        "label": "Dew Point Temperature",
        "unit_label": "C",
    },
    "wetBulbTemperature": {"label": "Wet Bulb Temperature", "unit_label": "C"},
    "precipitation3h": {
        "label": "3-Hour Precipitation Accumulation",
        "unit_label": "mm",
    },
    "capeSurface": {
        "label": "Convective Available Potential Energy From the Surface",
        "unit_label": "J/kg",
    },
    "totalPrecipitableWater": {
        "label": "Total Precipitable Water",
        "unit_label": "mm",
    },
    "totalCloudWater": {"label": "Total Cloud Water", "unit_label": "kg/m2"},
    "meanSeaLevelPressure": {
        "label": "Mean Sea Level Pressure",
        "unit_label": "hPa",
    },
    "miseryIndex": {"label": "Misery Index", "unit_label": "index"},
    "ultravioletIndex": {"label": "Ultraviolet Index", "unit_label": "index"},
    "instantaneousWindPowerDensity": {
        "label": "Instantaneous Wind Power Density",
        "unit_label": "W/m2",
    },
}


def _clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def _wet_bulb_temperature_c(temperature_c: float, relative_humidity: float) -> float:
    rh = _clamp(relative_humidity, 5.0, 99.0)
    return (
        temperature_c * math.atan(0.151977 * math.sqrt(rh + 8.313659))
        + math.atan(temperature_c + rh)
        - math.atan(rh - 1.676331)
        + 0.00391838 * (rh ** 1.5) * math.atan(0.023101 * rh)
        - 4.686035
    )


def _solar_incidence(
    latitude: float,
    longitude: float,
    sun_latitude: float,
    sun_longitude: float,
) -> float:
    latitude_radians = math.radians(latitude)
    sun_latitude_radians = math.radians(sun_latitude)
    delta_longitude_radians = math.radians(longitude - sun_longitude)
    return (
        math.sin(latitude_radians) * math.sin(sun_latitude_radians)
        + math.cos(latitude_radians)
        * math.cos(sun_latitude_radians)
        * math.cos(delta_longitude_radians)
    )


def _scalar_fields(
    *,
    timestamp_utc: datetime,
    latitude: float,
    longitude: float,
    level: str,
    sun_latitude: float,
    sun_longitude: float,
) -> dict[str, float]:
    profile = _WIND_LEVELS[level]
    latitude_radians = math.radians(latitude)
    longitude_radians = math.radians(longitude)
    hours = timestamp_utc.timestamp() / 3600.0
    day_of_year = timestamp_utc.timetuple().tm_yday

    season = math.sin((2.0 * math.pi * (day_of_year - 172)) / 365.2425)
    local_solar = _solar_incidence(
        latitude,
        longitude,
        sun_latitude,
        sun_longitude,
    )
    daylight = max(0.0, local_solar)
    tropicality = math.pow(max(0.0, math.cos(latitude_radians)), 1.6)
    midlatitude = _clamp(1.0 - (abs(abs(latitude) - 45.0) / 25.0), 0.0, 1.0)
    storm_track = midlatitude * (
        0.55
        + 0.45
        * math.sin((longitude_radians * 1.8) - (hours / 20.0) + (latitude_radians * 0.6))
    )
    storm_track = _clamp(storm_track, 0.0, 1.0)
    monsoon = max(0.0, math.sin(latitude_radians) * season)
    wave = math.sin((longitude_radians * 2.1) + (latitude_radians * 1.3) + (hours / 18.0))
    standing_wave = math.cos(
        (longitude_radians * 3.2) - (latitude_radians * 0.9) - (hours / 31.0)
    )

    u_mps, v_mps = _wind_components(timestamp_utc, latitude, longitude, profile)
    wind_speed_mps = math.sqrt((u_mps * u_mps) + (v_mps * v_mps))
    air_density = 1.225 * math.exp(-profile["altitude_km"] / 8.5)

    temperature_c = (
        -26.0
        + (56.0 * tropicality)
        - (profile["altitude_km"] * 6.2)
        + (12.0 * season * math.sin(latitude_radians))
        + (6.0 * daylight * (0.35 + (0.65 * tropicality)))
        - (2.5 * (1.0 - daylight) * (0.25 + (0.75 * tropicality)))
        + (4.5 * wave)
        + (2.0 * standing_wave)
    )

    relative_humidity = _clamp(
        18.0
        + (54.0 * tropicality)
        + (16.0 * storm_track)
        + (10.0 * monsoon)
        - (max(0.0, temperature_c - 24.0) * 0.9)
        - (profile["altitude_km"] * 1.7)
        + (12.0 * math.sin((longitude_radians * 1.4) - (hours / 28.0)))
        + (8.0 * math.cos((latitude_radians * 2.0) + (longitude_radians * 0.8) + (hours / 41.0))),
        5.0,
        100.0,
    )

    dew_point_c = temperature_c - ((100.0 - relative_humidity) / 5.0)
    if temperature_c > 32.0:
        dew_point_c -= (temperature_c - 32.0) * 0.02
    wet_bulb_c = _wet_bulb_temperature_c(temperature_c, relative_humidity)

    moisture_index = max(0.0, (relative_humidity - 55.0) / 45.0)
    precipitation_3h_mm = _clamp(
        (
            (moisture_index * 6.0)
            + (storm_track * 3.0)
            + (max(0.0, wet_bulb_c) * 0.08)
            + (daylight * 2.5)
            + max(0.0, wave)
        )
        * 4.0
        - 6.0,
        0.0,
        42.0,
    )

    cape_surface_jkg = _clamp(
        (
            math.pow(max(0.0, temperature_c - 18.0), 1.35)
            * (max(0.0, dew_point_c + 5.0) / 18.0)
            * (0.35 + tropicality)
            * (0.5 + daylight)
            * 42.0
        )
        + (storm_track * 350.0)
        + (monsoon * 250.0),
        0.0,
        5200.0,
    )

    total_precipitable_water_mm = _clamp(
        6.0
        + (32.0 * tropicality)
        + (22.0 * moisture_index)
        + (max(0.0, temperature_c) * 0.45)
        - (profile["altitude_km"] * 0.8)
        + (storm_track * 6.0),
        2.0,
        78.0,
    )

    total_cloud_water_kgm2 = _clamp(
        (storm_track * 0.9)
        + (moisture_index * 0.8)
        + (precipitation_3h_mm * 0.08)
        + (0.25 * max(0.0, math.sin((longitude_radians * 1.7) + (hours / 14.0)))),
        0.0,
        6.5,
    )

    mean_sea_level_pressure_hpa = _clamp(
        1013.2
        - ((temperature_c - 15.0) * 0.32)
        - (storm_track * 18.0)
        + (6.0 * math.sin((longitude_radians * 1.7) - (hours / 20.0)))
        + (4.0 * math.cos((latitude_radians * 3.1) + (longitude_radians * 0.7) + (hours / 33.0))),
        976.0,
        1048.0,
    )

    misery_index = _clamp(
        temperature_c + (0.15 * relative_humidity) + (max(0.0, dew_point_c) * 0.35),
        -10.0,
        62.0,
    )

    ultraviolet_index = _clamp(
        daylight
        * (1.5 + (9.5 * tropicality) + (profile["altitude_km"] * 0.3) - (total_cloud_water_kgm2 * 1.4)),
        0.0,
        15.0,
    )

    instantaneous_wind_power_density = _clamp(
        0.5 * air_density * (wind_speed_mps ** 3),
        0.0,
        5400.0,
    )

    return {
        "wind": round(wind_speed_mps, 3),
        "temperature": round(temperature_c, 3),
        "relativeHumidity": round(relative_humidity, 3),
        "dewPointTemperature": round(dew_point_c, 3),
        "wetBulbTemperature": round(wet_bulb_c, 3),
        "precipitation3h": round(precipitation_3h_mm, 3),
        "capeSurface": round(cape_surface_jkg, 3),
        "totalPrecipitableWater": round(total_precipitable_water_mm, 3),
        "totalCloudWater": round(total_cloud_water_kgm2, 3),
        "meanSeaLevelPressure": round(mean_sea_level_pressure_hpa, 3),
        "miseryIndex": round(misery_index, 3),
        "ultravioletIndex": round(ultraviolet_index, 3),
        "instantaneousWindPowerDensity": round(instantaneous_wind_power_density, 3),
    }


def get_weather_overlay_snapshot(
    *,
    overlay: str,
    timestamp_utc: str | None = None,
    level: str = "surface",
    grid_step_degrees: int = 15,
) -> WeatherOverlaySnapshotResponse:
    metadata = _WEATHER_OVERLAYS.get(overlay)
    if metadata is None:
        raise ValueError("Unsupported weather overlay.")
    if level not in _WIND_LEVELS:
        raise ValueError("Unsupported wind level.")

    effective_timestamp = _parse_timestamp_utc(timestamp_utc)
    julian_day = _julian_day(effective_timestamp)
    greenwich_mean_sidereal_degrees = _greenwich_mean_sidereal_degrees(julian_day)
    sun_ra, sun_dec, _ = _sun_equatorial_position(julian_day)
    sun_latitude, sun_longitude = _subpoint_from_right_ascension(
        sun_ra,
        sun_dec,
        greenwich_mean_sidereal_degrees,
    )
    values: list[WeatherOverlayValueResponse] = []
    min_value = math.inf
    max_value = -math.inf

    for latitude in range(-85, 86, grid_step_degrees):
        for longitude in range(-180, 180, grid_step_degrees):
            scalar_fields = _scalar_fields(
                timestamp_utc=effective_timestamp,
                latitude=float(latitude),
                longitude=float(longitude),
                level=level,
                sun_latitude=sun_latitude,
                sun_longitude=sun_longitude,
            )
            value = scalar_fields[overlay]
            min_value = min(min_value, value)
            max_value = max(max_value, value)
            values.append(
                WeatherOverlayValueResponse(
                    latitude=float(latitude),
                    longitude=float(longitude),
                    value=value,
                )
            )

    if not values:
        min_value = 0.0
        max_value = 1.0

    return WeatherOverlaySnapshotResponse(
        timestamp_utc=effective_timestamp.isoformat().replace("+00:00", "Z"),
        source=f"Preview weather overlay (procedural {metadata['label']} field)",
        overlay=overlay,
        overlay_label=metadata["label"],
        unit_label=metadata["unit_label"],
        level=level,
        grid_step_degrees=grid_step_degrees,
        min_value=round(min_value, 3),
        max_value=round(max_value, 3),
        values=values,
    )
