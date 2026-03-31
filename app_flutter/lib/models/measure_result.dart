import 'place_marker.dart';

class MeasureResult {
  const MeasureResult({
    required this.start,
    required this.end,
    required this.planeDistance,
    required this.planeDistanceLabel,
    required this.geodesicDistanceKm,
    required this.geodesicDistanceMiles,
    required this.distanceReferenceNote,
  });

  final PlaceMarker start;
  final PlaceMarker end;
  final double planeDistance;
  final String planeDistanceLabel;
  final double geodesicDistanceKm;
  final double geodesicDistanceMiles;
  final String distanceReferenceNote;

  factory MeasureResult.fromJson(Map<String, dynamic> json) {
    return MeasureResult(
      start: PlaceMarker.fromJson(json['start'] as Map<String, dynamic>),
      end: PlaceMarker.fromJson(json['end'] as Map<String, dynamic>),
      planeDistance: (json['plane_distance'] as num).toDouble(),
      planeDistanceLabel: json['plane_distance_label'] as String? ?? '',
      geodesicDistanceKm:
          (json['geodesic_distance_km'] as num?)?.toDouble() ?? 0,
      geodesicDistanceMiles:
          (json['geodesic_distance_miles'] as num?)?.toDouble() ?? 0,
      distanceReferenceNote:
          json['distance_reference_note'] as String? ?? '',
    );
  }
}
