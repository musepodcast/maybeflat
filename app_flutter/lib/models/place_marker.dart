class PlaceMarker {
  const PlaceMarker({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.x,
    required this.y,
    required this.zone,
  });

  final String name;
  final double latitude;
  final double longitude;
  final double x;
  final double y;
  final String zone;

  factory PlaceMarker.fromJson(Map<String, dynamic> json) {
    return PlaceMarker(
      name: json['name'] as String? ?? 'Unnamed',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      zone: json['zone'] as String? ?? 'inner_world',
    );
  }
}

