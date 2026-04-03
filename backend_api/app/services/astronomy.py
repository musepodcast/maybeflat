from __future__ import annotations

from datetime import datetime, timedelta, timezone
from functools import lru_cache
from math import asin, atan2, cos, degrees, radians, sin, sqrt

from app.schemas.map_models import (
    AstronomyBodyResponse,
    AstronomyEventListResponse,
    AstronomyEventResponse,
    AstronomyObserverResponse,
    AstronomySnapshotResponse,
    FlatPointResponse,
    TransformRequest,
)
from app.data.astronomy_events import ASTRONOMY_EVENTS
from app.services.flat_world import transform_point

_SUNRISE_ALTITUDE_DEGREES = -0.833


def _normalize_degrees(value: float) -> float:
    return value % 360.0


def _normalize_signed_degrees(value: float) -> float:
    normalized = (value + 180.0) % 360.0 - 180.0
    return 180.0 if normalized == -180.0 else normalized


def _parse_timestamp(timestamp_utc: str | None) -> datetime:
    if not timestamp_utc:
        return datetime.now(timezone.utc)

    normalized = timestamp_utc.strip().replace("Z", "+00:00")
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _julian_day(moment_utc: datetime) -> float:
    unix_epoch_julian_day = 2440587.5
    return unix_epoch_julian_day + (moment_utc.timestamp() / 86400.0)


def _greenwich_mean_sidereal_degrees(julian_day: float) -> float:
    centuries = (julian_day - 2451545.0) / 36525.0
    gmst = (
        280.46061837
        + 360.98564736629 * (julian_day - 2451545.0)
        + 0.000387933 * centuries * centuries
        - (centuries * centuries * centuries) / 38710000.0
    )
    return _normalize_degrees(gmst)


def _sun_equatorial_position(julian_day: float) -> tuple[float, float, float]:
    centuries = (julian_day - 2451545.0) / 36525.0
    mean_longitude = _normalize_degrees(
        280.46646 + centuries * (36000.76983 + 0.0003032 * centuries)
    )
    mean_anomaly = _normalize_degrees(
        357.52911 + centuries * (35999.05029 - 0.0001537 * centuries)
    )
    mean_anomaly_radians = radians(mean_anomaly)
    equation_of_center = (
        sin(mean_anomaly_radians)
        * (1.914602 - centuries * (0.004817 + 0.000014 * centuries))
        + sin(2 * mean_anomaly_radians)
        * (0.019993 - 0.000101 * centuries)
        + sin(3 * mean_anomaly_radians) * 0.000289
    )
    true_longitude = mean_longitude + equation_of_center
    omega = 125.04 - 1934.136 * centuries
    apparent_longitude = true_longitude - 0.00569 - 0.00478 * sin(radians(omega))
    mean_obliquity = 23.0 + (
        26.0
        + (
            21.448
            - centuries
            * (46.815 + centuries * (0.00059 - centuries * 0.001813))
        )
        / 60.0
    ) / 60.0
    true_obliquity = mean_obliquity + 0.00256 * cos(radians(omega))
    apparent_longitude_radians = radians(apparent_longitude)
    true_obliquity_radians = radians(true_obliquity)

    right_ascension = degrees(
        atan2(
            cos(true_obliquity_radians) * sin(apparent_longitude_radians),
            cos(apparent_longitude_radians),
        )
    )
    declination = degrees(
        asin(
            sin(true_obliquity_radians) * sin(apparent_longitude_radians),
        )
    )
    return (
        _normalize_degrees(right_ascension),
        declination,
        _normalize_degrees(apparent_longitude),
    )


def _moon_equatorial_position(julian_day: float) -> tuple[float, float, float]:
    days = julian_day - 2451543.5
    ascending_node = _normalize_degrees(125.1228 - 0.0529538083 * days)
    inclination = 5.1454
    argument_of_perigee = _normalize_degrees(318.0634 + 0.1643573223 * days)
    eccentricity = 0.0549
    mean_anomaly = _normalize_degrees(115.3654 + 13.0649929509 * days)

    eccentric_anomaly = mean_anomaly + degrees(
        eccentricity
        * sin(radians(mean_anomaly))
        * (1.0 + eccentricity * cos(radians(mean_anomaly)))
    )
    for _ in range(2):
        eccentric_anomaly_radians = radians(eccentric_anomaly)
        eccentric_anomaly -= (
            eccentric_anomaly
            - degrees(eccentricity * sin(eccentric_anomaly_radians))
            - mean_anomaly
        ) / (1.0 - eccentricity * cos(eccentric_anomaly_radians))

    xv = cos(radians(eccentric_anomaly)) - eccentricity
    yv = sqrt(1.0 - eccentricity * eccentricity) * sin(radians(eccentric_anomaly))
    true_anomaly = degrees(atan2(yv, xv))
    distance = sqrt(xv * xv + yv * yv)

    xh = distance * (
        cos(radians(ascending_node))
        * cos(radians(true_anomaly + argument_of_perigee))
        - sin(radians(ascending_node))
        * sin(radians(true_anomaly + argument_of_perigee))
        * cos(radians(inclination))
    )
    yh = distance * (
        sin(radians(ascending_node))
        * cos(radians(true_anomaly + argument_of_perigee))
        + cos(radians(ascending_node))
        * sin(radians(true_anomaly + argument_of_perigee))
        * cos(radians(inclination))
    )
    zh = distance * (
        sin(radians(true_anomaly + argument_of_perigee)) * sin(radians(inclination))
    )

    ecliptic_longitude = degrees(atan2(yh, xh))
    ecliptic_latitude = degrees(atan2(zh, sqrt(xh * xh + yh * yh)))
    obliquity = radians(23.4393 - 3.563e-7 * days)

    xe = xh
    ye = yh * cos(obliquity) - zh * sin(obliquity)
    ze = yh * sin(obliquity) + zh * cos(obliquity)
    right_ascension = degrees(atan2(ye, xe))
    declination = degrees(atan2(ze, sqrt(xe * xe + ye * ye)))
    return (
        _normalize_degrees(right_ascension),
        declination,
        _normalize_degrees(ecliptic_longitude),
    )


def _subpoint_from_right_ascension(
    right_ascension_degrees: float,
    declination_degrees: float,
    greenwich_mean_sidereal_degrees: float,
) -> tuple[float, float]:
    longitude = _normalize_signed_degrees(
        right_ascension_degrees - greenwich_mean_sidereal_degrees
    )
    latitude = max(-90.0, min(90.0, declination_degrees))
    return latitude, longitude


def _altitude_degrees(
    observer_latitude: float,
    observer_longitude: float,
    right_ascension_degrees: float,
    declination_degrees: float,
    greenwich_mean_sidereal_degrees: float,
) -> float:
    local_sidereal = _normalize_degrees(
        greenwich_mean_sidereal_degrees + observer_longitude
    )
    hour_angle = radians(
        _normalize_signed_degrees(local_sidereal - right_ascension_degrees)
    )
    observer_latitude_radians = radians(observer_latitude)
    declination_radians = radians(declination_degrees)
    altitude = asin(
        sin(observer_latitude_radians) * sin(declination_radians)
        + cos(observer_latitude_radians)
        * cos(declination_radians)
        * cos(hour_angle)
    )
    return degrees(altitude)


def _moon_phase_name(phase_angle_degrees: float) -> str:
    normalized = _normalize_degrees(phase_angle_degrees)
    if normalized < 22.5 or normalized >= 337.5:
        return "New Moon"
    if normalized < 67.5:
        return "Waxing Crescent"
    if normalized < 112.5:
        return "First Quarter"
    if normalized < 157.5:
        return "Waxing Gibbous"
    if normalized < 202.5:
        return "Full Moon"
    if normalized < 247.5:
        return "Waning Gibbous"
    if normalized < 292.5:
        return "Last Quarter"
    return "Waning Crescent"


def _transform_body_point(
    name: str,
    latitude: float,
    longitude: float,
) -> FlatPointResponse:
    return transform_point(
        TransformRequest(
            name=name,
            latitude=latitude,
            longitude=longitude,
        )
    )


def _sample_path(
    body_name: str,
    body_kind: str,
    center_time_utc: datetime,
    path_hours: int,
    step_minutes: int,
) -> list[FlatPointResponse]:
    half_window = timedelta(hours=path_hours / 2)
    start_time = center_time_utc - half_window
    steps = max(1, int((path_hours * 60) / step_minutes))
    path_points: list[FlatPointResponse] = []

    for step in range(steps + 1):
        sample_time = start_time + timedelta(minutes=step * step_minutes)
        sample_julian_day = _julian_day(sample_time)
        gmst = _greenwich_mean_sidereal_degrees(sample_julian_day)
        if body_kind == "sun":
            right_ascension, declination, _ = _sun_equatorial_position(
                sample_julian_day
            )
        else:
            right_ascension, declination, _ = _moon_equatorial_position(
                sample_julian_day
            )
        latitude, longitude = _subpoint_from_right_ascension(
            right_ascension,
            declination,
            gmst,
        )
        path_points.append(_transform_body_point(body_name, latitude, longitude))

    return path_points


@lru_cache(maxsize=256)
def _get_snapshot_cached(
    timestamp_minute_utc: str,
    observer_name: str | None,
    observer_latitude: float | None,
    observer_longitude: float | None,
    path_hours: int,
    step_minutes: int,
) -> AstronomySnapshotResponse:
    timestamp_utc = _parse_timestamp(timestamp_minute_utc)
    julian_day = _julian_day(timestamp_utc)
    gmst = _greenwich_mean_sidereal_degrees(julian_day)

    sun_ra, sun_dec, sun_ecliptic_longitude = _sun_equatorial_position(julian_day)
    sun_latitude, sun_longitude = _subpoint_from_right_ascension(sun_ra, sun_dec, gmst)
    sun_subpoint = _transform_body_point("Sun", sun_latitude, sun_longitude)

    moon_ra, moon_dec, moon_ecliptic_longitude = _moon_equatorial_position(julian_day)
    moon_latitude, moon_longitude = _subpoint_from_right_ascension(
        moon_ra,
        moon_dec,
        gmst,
    )
    moon_subpoint = _transform_body_point("Moon", moon_latitude, moon_longitude)

    phase_angle = _normalize_degrees(moon_ecliptic_longitude - sun_ecliptic_longitude)
    moon_illumination_fraction = (1.0 - cos(radians(phase_angle))) / 2.0
    moon_phase_name = _moon_phase_name(phase_angle)

    observer: AstronomyObserverResponse | None = None
    if observer_latitude is not None and observer_longitude is not None:
        sun_altitude = _altitude_degrees(
            observer_latitude,
            observer_longitude,
            sun_ra,
            sun_dec,
            gmst,
        )
        moon_altitude = _altitude_degrees(
            observer_latitude,
            observer_longitude,
            moon_ra,
            moon_dec,
            gmst,
        )
        observer = AstronomyObserverResponse(
            name=observer_name,
            latitude=round(observer_latitude, 6),
            longitude=round(observer_longitude, 6),
            sun_altitude_degrees=round(sun_altitude, 2),
            moon_altitude_degrees=round(moon_altitude, 2),
            is_daylight=sun_altitude > _SUNRISE_ALTITUDE_DEGREES,
            is_moon_visible=moon_altitude > 0.0,
            moon_illumination_fraction=round(moon_illumination_fraction, 4),
        )

    return AstronomySnapshotResponse(
        timestamp_utc=timestamp_utc.isoformat().replace("+00:00", "Z"),
        source="Approximate live astronomy from UTC time, solar geometry, and lunar ephemeris.",
        sun=AstronomyBodyResponse(
            name="Sun",
            subpoint=sun_subpoint,
            path=_sample_path("Sun", "sun", timestamp_utc, path_hours, step_minutes),
            phase_name=None,
            illumination_fraction=1.0,
        ),
        moon=AstronomyBodyResponse(
            name="Moon",
            subpoint=moon_subpoint,
            path=_sample_path("Moon", "moon", timestamp_utc, path_hours, step_minutes),
            phase_name=moon_phase_name,
            illumination_fraction=round(moon_illumination_fraction, 4),
        ),
        observer=observer,
    )


def get_astronomy_snapshot(
    timestamp_utc: str | None = None,
    observer_name: str | None = None,
    observer_latitude: float | None = None,
    observer_longitude: float | None = None,
    path_hours: int = 24,
    path_step_minutes: int = 30,
) -> AstronomySnapshotResponse:
    timestamp = _parse_timestamp(timestamp_utc)
    rounded_timestamp = timestamp.replace(microsecond=0)
    rounded_latitude = (
        round(observer_latitude, 6) if observer_latitude is not None else None
    )
    rounded_longitude = (
        round(observer_longitude, 6) if observer_longitude is not None else None
    )
    return _get_snapshot_cached(
        rounded_timestamp.isoformat().replace("+00:00", "Z"),
        observer_name,
        rounded_latitude,
        rounded_longitude,
        max(6, min(path_hours, 48)),
        max(10, min(path_step_minutes, 120)),
    )


def list_astronomy_events(
    event_type: str | None = None,
    subgroup: str | None = None,
    from_timestamp_utc: str | None = None,
    limit: int = 24,
) -> AstronomyEventListResponse:
    from_timestamp = _parse_timestamp(from_timestamp_utc) if from_timestamp_utc else None
    normalized_event_type = event_type.strip().lower() if event_type else None
    normalized_subgroup = subgroup.strip().lower() if subgroup else None

    filtered = []
    for event in ASTRONOMY_EVENTS:
        event_timestamp = _parse_timestamp(event["timestamp_utc"])
        if from_timestamp is not None and event_timestamp < from_timestamp:
            continue
        if normalized_event_type and event["event_type"].lower() != normalized_event_type:
            continue
        if normalized_subgroup:
            subtype = event["subtype"].lower()
            if normalized_subgroup == "solar" and not subtype.startswith("solar_"):
                continue
            if normalized_subgroup == "lunar" and not subtype.startswith("lunar_"):
                continue
        filtered.append(
            AstronomyEventResponse(
                id=event["id"],
                event_type=event["event_type"],
                subtype=event["subtype"],
                title=event["title"],
                timestamp_utc=event["timestamp_utc"],
                description=event.get("description"),
            )
        )

    filtered.sort(key=lambda event: event.timestamp_utc)
    return AstronomyEventListResponse(events=filtered[: max(1, min(limit, 64))])
