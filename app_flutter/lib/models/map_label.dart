class MapLabel {
  const MapLabel({
    required this.name,
    required this.layer,
    required this.x,
    required this.y,
    required this.minScale,
  });

  final String name;
  final String layer;
  final double x;
  final double y;
  final double minScale;

  factory MapLabel.fromJson(Map<String, dynamic> json) {
    return MapLabel(
      name: json['name'] as String? ?? 'Unnamed label',
      layer: json['layer'] as String? ?? 'city',
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      minScale: (json['min_scale'] as num?)?.toDouble() ?? 1,
    );
  }
}
