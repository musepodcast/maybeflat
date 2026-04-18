class WeatherOverlayValue {
  const WeatherOverlayValue({
    required this.latitude,
    required this.longitude,
    required this.value,
  });

  final double latitude;
  final double longitude;
  final double value;

  factory WeatherOverlayValue.fromJson(Map<String, dynamic> json) {
    return WeatherOverlayValue(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      value: (json['value'] as num?)?.toDouble() ?? 0,
    );
  }
}

class WeatherOverlaySnapshot {
  const WeatherOverlaySnapshot({
    required this.timestampUtc,
    required this.source,
    required this.overlay,
    required this.overlayLabel,
    required this.unitLabel,
    required this.level,
    required this.gridStepDegrees,
    required this.minValue,
    required this.maxValue,
    required this.values,
  });

  final DateTime timestampUtc;
  final String source;
  final String overlay;
  final String overlayLabel;
  final String unitLabel;
  final String level;
  final int gridStepDegrees;
  final double minValue;
  final double maxValue;
  final List<WeatherOverlayValue> values;

  factory WeatherOverlaySnapshot.fromJson(Map<String, dynamic> json) {
    return WeatherOverlaySnapshot(
      timestampUtc: DateTime.parse(
        json['timestamp_utc'] as String? ??
            DateTime.now().toUtc().toIso8601String(),
      ).toUtc(),
      source: json['source'] as String? ?? 'Weather overlay snapshot',
      overlay: json['overlay'] as String? ?? 'wind',
      overlayLabel: json['overlay_label'] as String? ?? 'Wind',
      unitLabel: json['unit_label'] as String? ?? '',
      level: json['level'] as String? ?? 'surface',
      gridStepDegrees: (json['grid_step_degrees'] as num?)?.toInt() ?? 15,
      minValue: (json['min_value'] as num?)?.toDouble() ?? 0,
      maxValue: (json['max_value'] as num?)?.toDouble() ?? 0,
      values: (json['values'] as List<dynamic>? ?? const [])
          .map((value) => WeatherOverlayValue.fromJson(value as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}
