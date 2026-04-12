from __future__ import annotations

from dataclasses import dataclass
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
_J2000_OBLIQUITY_RADIANS = radians(23.43928)


@dataclass(frozen=True)
class _PlanetaryElements:
    key: str
    name: str
    semi_major_axis_base: float
    semi_major_axis_rate: float
    eccentricity_base: float
    eccentricity_rate: float
    inclination_base: float
    inclination_rate: float
    mean_longitude_base: float
    mean_longitude_rate: float
    perihelion_longitude_base: float
    perihelion_longitude_rate: float
    ascending_node_base: float
    ascending_node_rate: float
    mean_anomaly_b: float = 0.0
    mean_anomaly_c: float = 0.0
    mean_anomaly_s: float = 0.0
    mean_anomaly_f: float = 0.0
    argument_of_perihelion_base: float | None = None
    mean_anomaly_base: float | None = None
    mean_motion_degrees_per_day: float | None = None
    epoch_julian_day: float = 2451545.0


_PLANETARY_ELEMENTS: dict[str, _PlanetaryElements] = {
    "mercury": _PlanetaryElements(
        key="mercury",
        name="Mercury",
        semi_major_axis_base=0.38709843,
        semi_major_axis_rate=0.00000000,
        eccentricity_base=0.20563661,
        eccentricity_rate=0.00002123,
        inclination_base=7.00559432,
        inclination_rate=-0.00590158,
        mean_longitude_base=252.25166724,
        mean_longitude_rate=149472.67486623,
        perihelion_longitude_base=77.45771895,
        perihelion_longitude_rate=0.15940013,
        ascending_node_base=48.33961819,
        ascending_node_rate=-0.12214182,
    ),
    "venus": _PlanetaryElements(
        key="venus",
        name="Venus",
        semi_major_axis_base=0.72332102,
        semi_major_axis_rate=-0.00000026,
        eccentricity_base=0.00676399,
        eccentricity_rate=-0.00005107,
        inclination_base=3.39777545,
        inclination_rate=0.00043494,
        mean_longitude_base=181.97970850,
        mean_longitude_rate=58517.81560260,
        perihelion_longitude_base=131.76755713,
        perihelion_longitude_rate=0.05679648,
        ascending_node_base=76.67261496,
        ascending_node_rate=-0.27274174,
    ),
    "earth": _PlanetaryElements(
        key="earth",
        name="Earth",
        semi_major_axis_base=1.00000018,
        semi_major_axis_rate=-0.00000003,
        eccentricity_base=0.01673163,
        eccentricity_rate=-0.00003661,
        inclination_base=-0.00054346,
        inclination_rate=-0.01337178,
        mean_longitude_base=100.46691572,
        mean_longitude_rate=35999.37306329,
        perihelion_longitude_base=102.93005885,
        perihelion_longitude_rate=0.31795260,
        ascending_node_base=-5.11260389,
        ascending_node_rate=-0.24123856,
    ),
    "mars": _PlanetaryElements(
        key="mars",
        name="Mars",
        semi_major_axis_base=1.52371243,
        semi_major_axis_rate=0.00000097,
        eccentricity_base=0.09336511,
        eccentricity_rate=0.00009149,
        inclination_base=1.85181869,
        inclination_rate=-0.00724757,
        mean_longitude_base=-4.56813164,
        mean_longitude_rate=19140.29934243,
        perihelion_longitude_base=-23.91744784,
        perihelion_longitude_rate=0.45223625,
        ascending_node_base=49.71320984,
        ascending_node_rate=-0.26852431,
    ),
    "jupiter": _PlanetaryElements(
        key="jupiter",
        name="Jupiter",
        semi_major_axis_base=5.20248019,
        semi_major_axis_rate=-0.00002864,
        eccentricity_base=0.04853590,
        eccentricity_rate=0.00018026,
        inclination_base=1.29861416,
        inclination_rate=-0.00322699,
        mean_longitude_base=34.33479152,
        mean_longitude_rate=3034.90371757,
        perihelion_longitude_base=14.27495244,
        perihelion_longitude_rate=0.18199196,
        ascending_node_base=100.29282654,
        ascending_node_rate=0.13024619,
        mean_anomaly_b=-0.00012452,
        mean_anomaly_c=0.06064060,
        mean_anomaly_s=-0.35635438,
        mean_anomaly_f=38.35125000,
    ),
    "saturn": _PlanetaryElements(
        key="saturn",
        name="Saturn",
        semi_major_axis_base=9.54149883,
        semi_major_axis_rate=-0.00003065,
        eccentricity_base=0.05550825,
        eccentricity_rate=-0.00032044,
        inclination_base=2.49424102,
        inclination_rate=0.00451969,
        mean_longitude_base=50.07571329,
        mean_longitude_rate=1222.11494724,
        perihelion_longitude_base=92.86136063,
        perihelion_longitude_rate=0.54179478,
        ascending_node_base=113.63998702,
        ascending_node_rate=-0.25015002,
        mean_anomaly_b=0.00025899,
        mean_anomaly_c=-0.13434469,
        mean_anomaly_s=0.87320147,
        mean_anomaly_f=38.35125000,
    ),
    "uranus": _PlanetaryElements(
        key="uranus",
        name="Uranus",
        semi_major_axis_base=19.18797948,
        semi_major_axis_rate=-0.00020455,
        eccentricity_base=0.04685740,
        eccentricity_rate=-0.00001550,
        inclination_base=0.77298127,
        inclination_rate=-0.00180155,
        mean_longitude_base=314.20276625,
        mean_longitude_rate=428.49512595,
        perihelion_longitude_base=172.43404441,
        perihelion_longitude_rate=0.09266985,
        ascending_node_base=73.96250215,
        ascending_node_rate=0.05739699,
        mean_anomaly_b=0.00058331,
        mean_anomaly_c=-0.97731848,
        mean_anomaly_s=0.17689245,
        mean_anomaly_f=7.67025000,
    ),
    "neptune": _PlanetaryElements(
        key="neptune",
        name="Neptune",
        semi_major_axis_base=30.06952752,
        semi_major_axis_rate=0.00006447,
        eccentricity_base=0.00895439,
        eccentricity_rate=0.00000818,
        inclination_base=1.77005520,
        inclination_rate=0.00022400,
        mean_longitude_base=304.22289287,
        mean_longitude_rate=218.46515314,
        perihelion_longitude_base=46.68158724,
        perihelion_longitude_rate=0.01009938,
        ascending_node_base=131.78635853,
        ascending_node_rate=-0.00606302,
        mean_anomaly_b=-0.00041348,
        mean_anomaly_c=0.68346318,
        mean_anomaly_s=-0.10162547,
        mean_anomaly_f=7.67025000,
    ),
    "pluto": _PlanetaryElements(
        key="pluto",
        name="Pluto",
        semi_major_axis_base=39.58862938517124,
        semi_major_axis_rate=0.0,
        eccentricity_base=0.2518378778576892,
        eccentricity_rate=0.0,
        inclination_base=17.14771140999114,
        inclination_rate=0.0,
        mean_longitude_base=0.0,
        mean_longitude_rate=0.0,
        perihelion_longitude_base=223.0013855701622,
        perihelion_longitude_rate=0.0,
        ascending_node_base=110.2923840543057,
        ascending_node_rate=0.0,
        argument_of_perihelion_base=113.7090015158565,
        mean_anomaly_base=38.68366347318184,
        mean_motion_degrees_per_day=0.003956838955553025,
        epoch_julian_day=2457588.5,
    ),
}
_DISPLAY_PLANET_KEYS = (
    "mercury",
    "venus",
    "mars",
    "jupiter",
    "saturn",
    "uranus",
    "neptune",
    "pluto",
)


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


def _planetary_centuries(julian_day: float) -> float:
    return (julian_day - 2451545.0) / 36525.0


def _solve_kepler(mean_anomaly_radians: float, eccentricity: float) -> float:
    eccentric_anomaly = mean_anomaly_radians
    for _ in range(8):
        delta = (
            eccentric_anomaly
            - eccentricity * sin(eccentric_anomaly)
            - mean_anomaly_radians
        ) / (1.0 - eccentricity * cos(eccentric_anomaly))
        eccentric_anomaly -= delta
        if abs(delta) < 1e-10:
            break
    return eccentric_anomaly


def _heliocentric_ecliptic_coordinates(
    julian_day: float,
    planet_key: str,
) -> tuple[float, float, float]:
    elements = _PLANETARY_ELEMENTS[planet_key]
    centuries = _planetary_centuries(julian_day)
    semi_major_axis = (
        elements.semi_major_axis_base + elements.semi_major_axis_rate * centuries
    )
    eccentricity = (
        elements.eccentricity_base + elements.eccentricity_rate * centuries
    )
    inclination = radians(
        elements.inclination_base + elements.inclination_rate * centuries
    )
    mean_longitude = (
        elements.mean_longitude_base + elements.mean_longitude_rate * centuries
    )
    perihelion_longitude = (
        elements.perihelion_longitude_base
        + elements.perihelion_longitude_rate * centuries
    )
    ascending_node = (
        elements.ascending_node_base + elements.ascending_node_rate * centuries
    )
    argument_of_perihelion_degrees = (
        elements.argument_of_perihelion_base
        if elements.argument_of_perihelion_base is not None
        else perihelion_longitude - ascending_node
    )
    argument_of_perihelion = radians(argument_of_perihelion_degrees)
    if (
        elements.mean_anomaly_base is not None
        and elements.mean_motion_degrees_per_day is not None
    ):
        mean_anomaly = _normalize_signed_degrees(
            elements.mean_anomaly_base
            + elements.mean_motion_degrees_per_day
            * (julian_day - elements.epoch_julian_day)
        )
    else:
        mean_anomaly = _normalize_signed_degrees(
            mean_longitude
            - perihelion_longitude
            + elements.mean_anomaly_b * centuries * centuries
            + elements.mean_anomaly_c
            * cos(radians(elements.mean_anomaly_f * centuries))
            + elements.mean_anomaly_s
            * sin(radians(elements.mean_anomaly_f * centuries))
        )
    eccentric_anomaly = _solve_kepler(radians(mean_anomaly), eccentricity)

    x_orbital = semi_major_axis * (cos(eccentric_anomaly) - eccentricity)
    y_orbital = (
        semi_major_axis
        * sqrt(max(0.0, 1.0 - eccentricity * eccentricity))
        * sin(eccentric_anomaly)
    )

    ascending_node_radians = radians(ascending_node)
    cos_omega = cos(argument_of_perihelion)
    sin_omega = sin(argument_of_perihelion)
    cos_node = cos(ascending_node_radians)
    sin_node = sin(ascending_node_radians)
    cos_inclination = cos(inclination)
    sin_inclination = sin(inclination)

    x_ecliptic = (
        (cos_omega * cos_node - sin_omega * sin_node * cos_inclination)
        * x_orbital
        + (-sin_omega * cos_node - cos_omega * sin_node * cos_inclination)
        * y_orbital
    )
    y_ecliptic = (
        (cos_omega * sin_node + sin_omega * cos_node * cos_inclination)
        * x_orbital
        + (-sin_omega * sin_node + cos_omega * cos_node * cos_inclination)
        * y_orbital
    )
    z_ecliptic = (
        sin_omega * sin_inclination * x_orbital
        + cos_omega * sin_inclination * y_orbital
    )
    return x_ecliptic, y_ecliptic, z_ecliptic


def _ecliptic_to_equatorial(
    x_ecliptic: float,
    y_ecliptic: float,
    z_ecliptic: float,
) -> tuple[float, float, float]:
    return (
        x_ecliptic,
        y_ecliptic * cos(_J2000_OBLIQUITY_RADIANS)
        - z_ecliptic * sin(_J2000_OBLIQUITY_RADIANS),
        y_ecliptic * sin(_J2000_OBLIQUITY_RADIANS)
        + z_ecliptic * cos(_J2000_OBLIQUITY_RADIANS),
    )


def _equatorial_position_from_vector(
    x_coordinate: float,
    y_coordinate: float,
    z_coordinate: float,
) -> tuple[float, float]:
    right_ascension = degrees(atan2(y_coordinate, x_coordinate))
    declination = degrees(
        atan2(z_coordinate, sqrt(x_coordinate * x_coordinate + y_coordinate * y_coordinate))
    )
    return _normalize_degrees(right_ascension), declination


def _planet_equatorial_position(
    julian_day: float,
    planet_key: str,
) -> tuple[float, float]:
    planet_x, planet_y, planet_z = _heliocentric_ecliptic_coordinates(
        julian_day,
        planet_key,
    )
    earth_x, earth_y, earth_z = _heliocentric_ecliptic_coordinates(
        julian_day,
        "earth",
    )
    x_equatorial, y_equatorial, z_equatorial = _ecliptic_to_equatorial(
        planet_x - earth_x,
        planet_y - earth_y,
        planet_z - earth_z,
    )
    return _equatorial_position_from_vector(
        x_equatorial,
        y_equatorial,
        z_equatorial,
    )


def _body_equatorial_position(
    julian_day: float,
    body_kind: str,
) -> tuple[float, float]:
    if body_kind == "sun":
        right_ascension, declination, _ = _sun_equatorial_position(julian_day)
        return right_ascension, declination
    if body_kind == "moon":
        right_ascension, declination, _ = _moon_equatorial_position(julian_day)
        return right_ascension, declination
    return _planet_equatorial_position(julian_day, body_kind)


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
        right_ascension, declination = _body_equatorial_position(
            sample_julian_day,
            body_kind,
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

    planets = []
    for planet_key in _DISPLAY_PLANET_KEYS:
        planet_name = _PLANETARY_ELEMENTS[planet_key].name
        planet_ra, planet_dec = _planet_equatorial_position(julian_day, planet_key)
        planet_latitude, planet_longitude = _subpoint_from_right_ascension(
            planet_ra,
            planet_dec,
            gmst,
        )
        planets.append(
            AstronomyBodyResponse(
                name=planet_name,
                subpoint=_transform_body_point(
                    planet_name,
                    planet_latitude,
                    planet_longitude,
                ),
                path=_sample_path(
                    planet_name,
                    planet_key,
                    timestamp_utc,
                    path_hours,
                    step_minutes,
                ),
                phase_name=None,
                illumination_fraction=None,
            )
        )

    return AstronomySnapshotResponse(
        timestamp_utc=timestamp_utc.isoformat().replace("+00:00", "Z"),
        source="Approximate live astronomy from UTC time, solar geometry, lunar ephemeris, and J2000 planetary elements.",
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
        planets=planets,
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
