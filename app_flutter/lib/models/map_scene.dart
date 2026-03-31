import 'map_label.dart';
import 'map_shape.dart';
import 'place_marker.dart';

class MapScene {
  const MapScene({
    required this.markers,
    required this.shapes,
    required this.labels,
    required this.shapeSource,
    required this.usingRealCoastlines,
    required this.boundarySource,
    required this.usingCountryBoundaries,
    required this.stateBoundarySource,
    required this.usingStateBoundaries,
    required this.detailLevel,
  });

  final List<PlaceMarker> markers;
  final List<MapShape> shapes;
  final List<MapLabel> labels;
  final String shapeSource;
  final bool usingRealCoastlines;
  final String boundarySource;
  final bool usingCountryBoundaries;
  final String stateBoundarySource;
  final bool usingStateBoundaries;
  final String detailLevel;

  factory MapScene.fromJson(Map<String, dynamic> json) {
    return MapScene(
      markers: (json['markers'] as List<dynamic>? ?? const [])
          .map((marker) => PlaceMarker.fromJson(marker as Map<String, dynamic>))
          .toList(),
      shapes: (json['shapes'] as List<dynamic>? ?? const [])
          .map((shape) => MapShape.fromJson(shape as Map<String, dynamic>))
          .toList(),
      labels: (json['labels'] as List<dynamic>? ?? const [])
          .map((label) => MapLabel.fromJson(label as Map<String, dynamic>))
          .toList(),
      shapeSource: json['shape_source'] as String? ?? 'prototype',
      usingRealCoastlines: json['using_real_coastlines'] as bool? ?? false,
      boundarySource: json['boundary_source'] as String? ?? 'unavailable',
      usingCountryBoundaries:
          json['using_country_boundaries'] as bool? ?? false,
      stateBoundarySource:
          json['state_boundary_source'] as String? ?? 'unavailable',
      usingStateBoundaries: json['using_state_boundaries'] as bool? ?? false,
      detailLevel: json['detail_level'] as String? ?? 'desktop',
    );
  }
}
