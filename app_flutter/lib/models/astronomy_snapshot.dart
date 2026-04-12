import 'place_marker.dart';

class AstronomyBody {
  const AstronomyBody({
    required this.name,
    required this.subpoint,
    required this.path,
    required this.phaseName,
    required this.illuminationFraction,
  });

  final String name;
  final PlaceMarker subpoint;
  final List<PlaceMarker> path;
  final String? phaseName;
  final double? illuminationFraction;

  factory AstronomyBody.fromJson(Map<String, dynamic> json) {
    return AstronomyBody(
      name: json['name'] as String? ?? 'Body',
      subpoint: PlaceMarker.fromJson(
        json['subpoint'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      path: (json['path'] as List<dynamic>? ?? const [])
          .map((point) => PlaceMarker.fromJson(point as Map<String, dynamic>))
          .toList(growable: false),
      phaseName: json['phase_name'] as String?,
      illuminationFraction: (json['illumination_fraction'] as num?)?.toDouble(),
    );
  }
}

class AstronomyObserver {
  const AstronomyObserver({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.sunAltitudeDegrees,
    required this.moonAltitudeDegrees,
    required this.isDaylight,
    required this.isMoonVisible,
    required this.moonIlluminationFraction,
  });

  final String? name;
  final double latitude;
  final double longitude;
  final double sunAltitudeDegrees;
  final double moonAltitudeDegrees;
  final bool isDaylight;
  final bool isMoonVisible;
  final double moonIlluminationFraction;

  factory AstronomyObserver.fromJson(Map<String, dynamic> json) {
    return AstronomyObserver(
      name: json['name'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      sunAltitudeDegrees:
          (json['sun_altitude_degrees'] as num?)?.toDouble() ?? 0,
      moonAltitudeDegrees:
          (json['moon_altitude_degrees'] as num?)?.toDouble() ?? 0,
      isDaylight: json['is_daylight'] as bool? ?? false,
      isMoonVisible: json['is_moon_visible'] as bool? ?? false,
      moonIlluminationFraction:
          (json['moon_illumination_fraction'] as num?)?.toDouble() ?? 0,
    );
  }
}

class AstronomySnapshot {
  const AstronomySnapshot({
    required this.timestampUtc,
    required this.source,
    required this.sun,
    required this.moon,
    required this.planets,
    required this.observer,
  });

  final DateTime timestampUtc;
  final String source;
  final AstronomyBody sun;
  final AstronomyBody moon;
  final List<AstronomyBody> planets;
  final AstronomyObserver? observer;

  factory AstronomySnapshot.fromJson(Map<String, dynamic> json) {
    return AstronomySnapshot(
      timestampUtc: DateTime.parse(
        json['timestamp_utc'] as String? ??
            DateTime.now().toUtc().toIso8601String(),
      ).toUtc(),
      source: json['source'] as String? ?? 'Astronomy snapshot',
      sun: AstronomyBody.fromJson(
        json['sun'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      moon: AstronomyBody.fromJson(
        json['moon'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      planets: (json['planets'] as List<dynamic>? ?? const [])
          .map((body) => AstronomyBody.fromJson(body as Map<String, dynamic>))
          .toList(growable: false),
      observer: json['observer'] == null
          ? null
          : AstronomyObserver.fromJson(
              json['observer'] as Map<String, dynamic>),
    );
  }
}
