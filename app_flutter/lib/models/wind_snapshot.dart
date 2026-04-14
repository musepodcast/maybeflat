class WindVector {
  const WindVector({
    required this.latitude,
    required this.longitude,
    required this.uMps,
    required this.vMps,
    required this.speedMps,
  });

  final double latitude;
  final double longitude;
  final double uMps;
  final double vMps;
  final double speedMps;

  factory WindVector.fromJson(Map<String, dynamic> json) {
    return WindVector(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      uMps: (json['u_mps'] as num?)?.toDouble() ?? 0,
      vMps: (json['v_mps'] as num?)?.toDouble() ?? 0,
      speedMps: (json['speed_mps'] as num?)?.toDouble() ?? 0,
    );
  }
}

class WindSnapshot {
  const WindSnapshot({
    required this.timestampUtc,
    required this.source,
    required this.level,
    required this.gridStepDegrees,
    required this.minSpeedMps,
    required this.maxSpeedMps,
    required this.vectors,
  });

  final DateTime timestampUtc;
  final String source;
  final String level;
  final int gridStepDegrees;
  final double minSpeedMps;
  final double maxSpeedMps;
  final List<WindVector> vectors;

  factory WindSnapshot.fromJson(Map<String, dynamic> json) {
    return WindSnapshot(
      timestampUtc: DateTime.parse(
        json['timestamp_utc'] as String? ??
            DateTime.now().toUtc().toIso8601String(),
      ).toUtc(),
      source: json['source'] as String? ?? 'Wind snapshot',
      level: json['level'] as String? ?? 'surface',
      gridStepDegrees: (json['grid_step_degrees'] as num?)?.toInt() ?? 15,
      minSpeedMps: (json['min_speed_mps'] as num?)?.toDouble() ?? 0,
      maxSpeedMps: (json['max_speed_mps'] as num?)?.toDouble() ?? 0,
      vectors: (json['vectors'] as List<dynamic>? ?? const [])
          .map((vector) => WindVector.fromJson(vector as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}
