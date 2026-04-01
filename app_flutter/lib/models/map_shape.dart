import 'dart:ui';

class MapPoint {
  const MapPoint({
    required this.x,
    required this.y,
  });

  final double x;
  final double y;

  factory MapPoint.fromJson(Map<String, dynamic> json) {
    return MapPoint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
    );
  }
}

class MapRing {
  const MapRing({
    required this.closed,
    required this.points,
  });

  final bool closed;
  final List<MapPoint> points;

  factory MapRing.fromJson(Map<String, dynamic> json) {
    return MapRing(
      closed: json['closed'] as bool? ?? true,
      points: (json['points'] as List<dynamic>? ?? const [])
          .map((point) => MapPoint.fromJson(point as Map<String, dynamic>))
          .toList(),
    );
  }
}

class MapShape {
  const MapShape({
    required this.name,
    required this.role,
    required this.fill,
    required this.stroke,
    required this.rings,
    this.timeZoneLabel,
    this.timeZoneOffsetMinutes,
  });

  final String name;
  final String role;
  final String fill;
  final String stroke;
  final List<MapRing> rings;
  final String? timeZoneLabel;
  final int? timeZoneOffsetMinutes;

  Color get fillColor => _parseHexColor(fill);
  Color get strokeColor => _parseHexColor(stroke);

  factory MapShape.fromJson(Map<String, dynamic> json) {
    final ringPayload = json['rings'] as List<dynamic>?;
    final legacyPoints = json['points'] as List<dynamic>?;

    return MapShape(
      name: json['name'] as String? ?? 'Unnamed shape',
      role: json['role'] as String? ?? 'land',
      fill: json['fill'] as String? ?? '#CCCCCC',
      stroke: json['stroke'] as String? ?? '#333333',
      timeZoneLabel: json['time_zone_label'] as String?,
      timeZoneOffsetMinutes: json['time_zone_offset_minutes'] as int?,
      rings: ringPayload != null
          ? ringPayload
              .map((ring) => MapRing.fromJson(ring as Map<String, dynamic>))
              .toList()
          : (legacyPoints != null && legacyPoints.isNotEmpty)
              ? [
                  MapRing(
                    closed: json['closed'] as bool? ?? true,
                    points: legacyPoints
                        .map((point) => MapPoint.fromJson(point as Map<String, dynamic>))
                        .toList(),
                  ),
                ]
              : const [],
    );
  }
}

Color _parseHexColor(String value) {
  final normalized = value.replaceFirst('#', '');
  final argb = normalized.length == 6 ? 'FF$normalized' : normalized;
  return Color(int.parse(argb, radix: 16));
}
