import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/astronomy_snapshot.dart';
import '../models/map_label.dart';
import '../models/map_shape.dart';
import '../models/place_marker.dart';
import '../models/sky_catalog.dart';
import '../models/weather_overlay_snapshot.dart';
import '../models/wind_snapshot.dart';
import '../services/sky_catalog_loader.dart';

class MapTapLocation {
  const MapTapLocation({
    required this.latitude,
    required this.longitude,
    required this.x,
    required this.y,
    required this.zone,
  });

  final double latitude;
  final double longitude;
  final double x;
  final double y;
  final String zone;
}

const double _innerWorldMinLatitude = -60;
const double _innerWorldRadius = 0.85;
const double _outerRingRadius = 1.0;
const String _tileCacheVersion = '20260405-shared-v1';
const String _sharedTileSet = 'shared-v1';

double _latitudeToRadiusRatio(double latitude) {
  if (latitude >= _innerWorldMinLatitude) {
    const span = 90.0 - _innerWorldMinLatitude;
    return ((90.0 - latitude) / span) * _innerWorldRadius;
  }

  const antarcticSpan = 30.0;
  final antarcticProgress =
      (latitude - _innerWorldMinLatitude).abs() / antarcticSpan;
  return _innerWorldRadius +
      antarcticProgress * (_outerRingRadius - _innerWorldRadius);
}

double _longitudeToThetaRadians(double longitude) {
  final thetaDegrees = (-longitude - 90.0) % 360.0;
  return thetaDegrees * math.pi / 180;
}

String _formatLatitudeLabel(double latitude) {
  if (latitude == 0) {
    return '0';
  }
  return latitude > 0
      ? '${latitude.abs().round()}N'
      : '${latitude.abs().round()}S';
}

String _formatLongitudeLabel(int longitude) {
  if (longitude == 0) {
    return '0';
  }
  if (longitude == 180 || longitude == -180) {
    return '180';
  }
  return longitude > 0 ? '${longitude.abs()}E' : '${longitude.abs()}W';
}

bool _isSharedSouthWestLabel(double latitude, int longitude) {
  return latitude.round() == -90 && longitude == -90;
}

List<double> _buildLatitudeGridValues(int stepDegrees) {
  final values = <int>{60, 0, -60, -90};
  for (var latitude = -90; latitude <= 90; latitude += 1) {
    if (latitude % stepDegrees == 0) {
      values.add(latitude);
    }
  }

  final ordered = values.toList()..sort((a, b) => b.compareTo(a));
  return ordered
      .where((latitude) => latitude < 90)
      .map((latitude) => latitude.toDouble())
      .toList(growable: false);
}

List<int> _buildLongitudeGridValues(int stepDegrees) {
  final values = <int>{-180, -90, 0, 90};
  for (var longitude = -180; longitude < 180; longitude += 1) {
    if (longitude % stepDegrees == 0) {
      values.add(longitude);
    }
  }

  final ordered = values.toList()..sort();
  return ordered.where((longitude) => longitude < 180).toList(growable: false);
}

int _gridLabelInterval(int stepDegrees) {
  if (stepDegrees <= 15) {
    return 30;
  }
  if (stepDegrees <= 20) {
    return 60;
  }
  return stepDegrees;
}

bool _isMajorLatitude(double latitude, int stepDegrees) {
  final roundedLatitude = latitude.round();
  if (roundedLatitude == 60 ||
      roundedLatitude == 0 ||
      roundedLatitude == -60 ||
      roundedLatitude == -90) {
    return true;
  }
  return roundedLatitude % _gridLabelInterval(stepDegrees) == 0;
}

bool _isMajorLongitude(int longitude, int stepDegrees) {
  if (longitude == -180 ||
      longitude == -90 ||
      longitude == 0 ||
      longitude == 90) {
    return true;
  }
  return longitude % _gridLabelInterval(stepDegrees) == 0;
}

double _longitudeDistanceDegrees(double left, double right) {
  final wrapped = ((left - right + 540) % 360) - 180;
  return wrapped.abs();
}

double _gridLongitudeLabelFontSize(int stepDegrees, double viewScale) {
  final densityBase = switch (stepDegrees) {
    <= 5 => 6.6,
    <= 10 => 7.4,
    <= 15 => 8.4,
    <= 20 => 9.2,
    <= 30 => 10.0,
    _ => 10.6,
  };
  final scaledBase = densityBase / math.pow(viewScale.clamp(1.0, 8.0), 0.26);
  return scaledBase.clamp(6.2, 10.6).toDouble();
}

double _gridLatitudeLabelFontSize(int stepDegrees, double viewScale) {
  final densityBase = switch (stepDegrees) {
    <= 5 => 8.6,
    <= 10 => 9.4,
    <= 15 => 10.2,
    <= 20 => 10.8,
    <= 30 => 11.4,
    _ => 12.0,
  };
  final scaledBase = densityBase / math.pow(viewScale.clamp(1.0, 8.0), 0.18);
  return scaledBase.clamp(7.8, 12.0).toDouble();
}

double _screenStableLabelScale(double viewScale) {
  return 1 / viewScale.clamp(1.0, 24.0);
}

double _layerLabelFontSize(String layer, double viewScale) {
  final baseSize = switch (layer) {
    'continent' => 16.5,
    'country' => 13.0,
    'state' => 9.8,
    'capital_world' => 10.6,
    'city_world' => 9.6,
    'city_major' => 11.0,
    'city_regional' => 10.0,
    'city_local' => 9.0,
    'city_detail' => 8.4,
    _ => 11.0,
  };
  final minSize = switch (layer) {
    'continent' => 10.2,
    'country' => 8.5,
    'state' => 6.8,
    'capital_world' => 7.0,
    'city_world' => 6.4,
    'city_major' => 7.5,
    'city_regional' => 6.8,
    'city_local' => 6.2,
    'city_detail' => 5.8,
    _ => 7.0,
  };
  final scaledSize = baseSize / math.pow(viewScale.clamp(1.0, 24.0), 0.18);
  return scaledSize.clamp(minSize, baseSize).toDouble();
}

double _markerLabelFontSize(double viewScale) {
  final scaledSize = 12 / math.pow(viewScale.clamp(1.0, 24.0), 0.16);
  return scaledSize.clamp(7.2, 12.0).toDouble();
}

double _shapeLabelFontSize(double viewScale) {
  final scaledSize = 12 / math.pow(viewScale.clamp(1.0, 24.0), 0.16);
  return scaledSize.clamp(7.0, 12.0).toDouble();
}

double _screenStableRadius(
  double baseRadius,
  double viewScale, {
  double minRadius = 1.2,
}) {
  final scaledRadius = baseRadius / math.pow(viewScale.clamp(1.0, 24.0), 0.55);
  return scaledRadius.clamp(minRadius, baseRadius).toDouble();
}

bool _isCityLayer(String layer) => layer.startsWith('city');

bool _isCapitalLayer(String layer) => layer.startsWith('capital');

bool _isPointLabelLayer(String layer) =>
    _isCityLayer(layer) || _isCapitalLayer(layer);

double _cityLabelDotRadius(String layer, double viewScale) {
  final baseRadius = switch (layer) {
    'city_world' => 1.0,
    'city_major' => 1.6,
    'city_regional' => 1.2,
    'city_local' => 0.95,
    'city_detail' => 0.72,
    _ => 1.0,
  };
  final minRadius = switch (layer) {
    'city_world' => 0.45,
    'city_major' => 0.7,
    'city_regional' => 0.55,
    'city_local' => 0.42,
    'city_detail' => 0.32,
    _ => 0.45,
  };
  final scaledRadius = baseRadius / math.pow(viewScale.clamp(1.0, 24.0), 0.82);
  return scaledRadius.clamp(minRadius, baseRadius).toDouble();
}

double _capitalLabelStarRadius(double viewScale) {
  final scaledRadius = 1.25 / math.pow(viewScale.clamp(1.0, 24.0), 0.78);
  return scaledRadius.clamp(0.55, 1.25).toDouble();
}

List<int> _buildTimeZoneOffsets() {
  return List<int>.generate(24, (index) => index - 12, growable: false);
}

String _formatUtcOffsetLabel(int offsetHours) {
  if (offsetHours == 0) {
    return 'UTC';
  }
  final sign = offsetHours > 0 ? '+' : '';
  return 'UTC$sign$offsetHours';
}

bool _isCelsiusWeatherUnit(String unitLabel) {
  return unitLabel.trim().toLowerCase() == 'c';
}

double _celsiusToFahrenheit(double valueC) {
  return (valueC * 9 / 5) + 32;
}

String _weatherUnitLabelForDisplay(
  String unitLabel, {
  bool includeFahrenheitForCelsius = false,
}) {
  if (_isCelsiusWeatherUnit(unitLabel)) {
    return includeFahrenheitForCelsius ? '°C / °F' : '°C';
  }
  return unitLabel;
}

String _weatherValueForDisplay(
  double value,
  String unitLabel, {
  bool includeFahrenheitForCelsius = false,
  bool multilineForFahrenheit = false,
}) {
  if (_isCelsiusWeatherUnit(unitLabel)) {
    final celsiusText = '${value.toStringAsFixed(1)}°C';
    if (!includeFahrenheitForCelsius) {
      return celsiusText;
    }
    final fahrenheitText =
        '${_celsiusToFahrenheit(value).toStringAsFixed(1)}°F';
    return multilineForFahrenheit
        ? '$celsiusText\n$fahrenheitText'
        : '$celsiusText / $fahrenheitText';
  }
  final trimmedUnit = unitLabel.trim();
  return trimmedUnit.isEmpty
      ? value.toStringAsFixed(1)
      : '${value.toStringAsFixed(1)} $trimmedUnit';
}

Offset _legendAnchor({
  required Rect visibleSceneRect,
  required double viewScale,
  required double legendWidth,
  required double legendHeight,
  required bool alignRight,
  required double sceneWidth,
  double horizontalInsetInScreen = 40.0,
  double topInsetInScreen = 18.0,
}) {
  final sideInset = sceneWidth < 560 ? 36.0 : horizontalInsetInScreen;
  final x = alignRight
      ? visibleSceneRect.right -
          ((legendWidth / 2) + sideInset) / viewScale.clamp(1.0, 24.0)
      : visibleSceneRect.left +
          ((legendWidth / 2) + sideInset) / viewScale.clamp(1.0, 24.0);
  final y = visibleSceneRect.top +
      ((legendHeight / 2) + topInsetInScreen) / viewScale.clamp(1.0, 24.0);
  return Offset(x, y);
}

double _timeZoneLabelFontSize(double viewScale) {
  final scaledBase = 9.8 / math.pow(viewScale.clamp(1.0, 24.0), 0.14);
  return scaledBase.clamp(7.6, 9.8).toDouble();
}

Offset _screenOffsetToScene(
  Offset offset,
  double viewScale,
) {
  return Offset(offset.dx / viewScale, offset.dy / viewScale);
}

double _mapRadiusScaleForSize(Size size) {
  return size.width < 560 ? 0.935 : 0.94;
}

bool _rectIntersectsDisk(Rect rect, Offset center, double radius) {
  final nearestX = rect.left > center.dx
      ? rect.left
      : rect.right < center.dx
          ? rect.right
          : center.dx;
  final nearestY = rect.top > center.dy
      ? rect.top
      : rect.bottom < center.dy
          ? rect.bottom
          : center.dy;
  final deltaX = center.dx - nearestX;
  final deltaY = center.dy - nearestY;
  return (deltaX * deltaX) + (deltaY * deltaY) <= (radius * radius);
}

class _GridHoverData {
  const _GridHoverData({
    required this.latitude,
    required this.longitude,
    required this.anchor,
  });

  final double latitude;
  final int longitude;
  final Offset anchor;
}

class _TileRange {
  const _TileRange({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final int minX;
  final int maxX;
  final int minY;
  final int maxY;
}

class _TileVisualRequest {
  const _TileVisualRequest({
    required this.x,
    required this.y,
    required this.priority,
  });

  final int x;
  final int y;
  final double priority;
}

enum EdgeRenderMode { coastline, country, both }

String _edgeModeSlug(EdgeRenderMode edgeMode) {
  return switch (edgeMode) {
    EdgeRenderMode.coastline => 'coastline',
    EdgeRenderMode.country => 'country',
    EdgeRenderMode.both => 'both',
  };
}

Offset _projectMapPoint(Offset center, double radius, double x, double y) {
  return Offset(
    center.dx + x * radius,
    center.dy + y * radius,
  );
}

Offset _projectLatLonPoint(
  Offset center,
  double mapRadius,
  double latitude,
  double longitude,
) {
  final radiusRatio = _latitudeToRadiusRatio(latitude);
  final theta = _longitudeToThetaRadians(longitude);
  return Offset(
    center.dx + math.cos(theta) * mapRadius * radiusRatio,
    center.dy + math.sin(theta) * mapRadius * radiusRatio,
  );
}

double _normalizeSignedDegrees(double value) {
  final normalized = (value + 540) % 360;
  return normalized - 180;
}

double _skyLongitudeDegrees(
  double rightAscensionHours,
  double siderealDegrees,
) {
  return _normalizeSignedDegrees((rightAscensionHours * 15) - siderealDegrees);
}

Offset _projectSkyCoordinatePoint(
  Offset center,
  double mapRadius, {
  required double rightAscensionHours,
  required double declinationDegrees,
  required double siderealDegrees,
}) {
  return _projectLatLonPoint(
    center,
    mapRadius,
    declinationDegrees,
    _skyLongitudeDegrees(rightAscensionHours, siderealDegrees),
  );
}

double _hemisphereIncidence(
  double latitude,
  double longitude,
  double sourceLatitude,
  double sourceLongitude,
) {
  final latitudeRadians = latitude * math.pi / 180;
  final sourceLatitudeRadians = sourceLatitude * math.pi / 180;
  final deltaLongitude = (longitude - sourceLongitude) * math.pi / 180;
  return math.sin(latitudeRadians) * math.sin(sourceLatitudeRadians) +
      math.cos(latitudeRadians) *
          math.cos(sourceLatitudeRadians) *
          math.cos(deltaLongitude);
}

double _smoothStep(double edge0, double edge1, double value) {
  final t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0).toDouble();
  return t * t * (3.0 - (2.0 * t));
}

double _nightSkyVisibility(
  AstronomySnapshot snapshot, {
  required double latitude,
  required double longitude,
  bool forceVisible = false,
}) {
  if (forceVisible) {
    return 1.0;
  }
  final sunIncidence = _hemisphereIncidence(
    latitude,
    longitude,
    snapshot.sun.subpoint.latitude,
    snapshot.sun.subpoint.longitude,
  );
  final daylightBlend = _smoothStep(-0.18, 0.06, sunIncidence);
  final moonIncidence = _hemisphereIncidence(
    latitude,
    longitude,
    snapshot.moon.subpoint.latitude,
    snapshot.moon.subpoint.longitude,
  ).clamp(0.0, 1.0);
  final moonStrength = (snapshot.moon.illuminationFraction ?? 0) * 0.18;
  final moonWashout = moonStrength * moonIncidence * (1.0 - daylightBlend);
  return (1.0 - daylightBlend - moonWashout).clamp(0.0, 1.0).toDouble();
}

class _PlanetVisualStyle {
  const _PlanetVisualStyle({
    required this.pathColor,
    required this.bodyColor,
    required this.glowColor,
    required this.baseRadius,
  });

  final Color pathColor;
  final Color bodyColor;
  final Color glowColor;
  final double baseRadius;
}

const Map<String, _PlanetVisualStyle> _planetVisualStyles =
    <String, _PlanetVisualStyle>{
  'Mercury': _PlanetVisualStyle(
    pathColor: Color(0xB3B9C1C9),
    bodyColor: Color(0xFFD0D6DD),
    glowColor: Color(0x66F1F5F9),
    baseRadius: 5.2,
  ),
  'Venus': _PlanetVisualStyle(
    pathColor: Color(0xB3F0C06B),
    bodyColor: Color(0xFFF0C06B),
    glowColor: Color(0x66FFE4A8),
    baseRadius: 6.2,
  ),
  'Mars': _PlanetVisualStyle(
    pathColor: Color(0xB3E06D5C),
    bodyColor: Color(0xFFE06D5C),
    glowColor: Color(0x66FFB5A8),
    baseRadius: 5.8,
  ),
  'Jupiter': _PlanetVisualStyle(
    pathColor: Color(0xB3DE9A72),
    bodyColor: Color(0xFFE1A57E),
    glowColor: Color(0x66F7D7B8),
    baseRadius: 6.8,
  ),
  'Saturn': _PlanetVisualStyle(
    pathColor: Color(0xB3D7C27B),
    bodyColor: Color(0xFFD9C88A),
    glowColor: Color(0x66F7E8B8),
    baseRadius: 6.4,
  ),
  'Uranus': _PlanetVisualStyle(
    pathColor: Color(0xB36AC7D7),
    bodyColor: Color(0xFF8BD7E7),
    glowColor: Color(0x669FEFFF),
    baseRadius: 6.0,
  ),
  'Neptune': _PlanetVisualStyle(
    pathColor: Color(0xB36688E0),
    bodyColor: Color(0xFF7792F0),
    glowColor: Color(0x66B5C7FF),
    baseRadius: 6.0,
  ),
  'Pluto': _PlanetVisualStyle(
    pathColor: Color(0xB39E8D7B),
    bodyColor: Color(0xFFB49C87),
    glowColor: Color(0x66E3D4C7),
    baseRadius: 4.8,
  ),
};

Path _buildStarPath(
  Offset center,
  double outerRadius, {
  double innerRadiusFactor = 0.46,
  int points = 5,
}) {
  final path = Path();
  final innerRadius = outerRadius * innerRadiusFactor;
  for (var pointIndex = 0; pointIndex < points * 2; pointIndex += 1) {
    final radius = pointIndex.isEven ? outerRadius : innerRadius;
    final angle = (-math.pi / 2) + (pointIndex * math.pi / points);
    final point = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
    if (pointIndex == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
  }
  path.close();
  return path;
}

List<Offset> _projectMapRing(
  Offset center,
  double mapRadius,
  MapRing ring,
) {
  return ring.points
      .map((point) => _projectMapPoint(center, mapRadius, point.x, point.y))
      .toList(growable: false);
}

Path _buildProjectedShapePath(
    List<MapRing> rings, Offset center, double mapRadius) {
  final path = Path()..fillType = PathFillType.evenOdd;
  for (final ring in rings) {
    if (ring.points.isEmpty) {
      continue;
    }
    final firstPoint = _projectMapPoint(
      center,
      mapRadius,
      ring.points.first.x,
      ring.points.first.y,
    );
    path.moveTo(firstPoint.dx, firstPoint.dy);

    for (final point in ring.points.skip(1)) {
      final projected = _projectMapPoint(center, mapRadius, point.x, point.y);
      path.lineTo(projected.dx, projected.dy);
    }

    if (ring.closed) {
      path.close();
    }
  }
  return path;
}

class _ProjectedShapeEntry {
  const _ProjectedShapeEntry({
    required this.shape,
    required this.path,
    required this.bounds,
    required this.hasClosedRing,
  });

  final MapShape shape;
  final Path path;
  final Rect bounds;
  final bool hasClosedRing;
}

class _ProjectedSceneCache {
  const _ProjectedSceneCache({
    required this.size,
    required this.center,
    required this.radius,
    required this.mapRadius,
    required this.sourceShapes,
    required this.landEntries,
    required this.boundaryEntries,
    required this.stateBoundaryEntries,
    required this.timeZoneEntries,
    required this.landClipPath,
    required this.projectedLandRings,
  });

  final Size size;
  final Offset center;
  final double radius;
  final double mapRadius;
  final List<MapShape> sourceShapes;
  final List<_ProjectedShapeEntry> landEntries;
  final List<_ProjectedShapeEntry> boundaryEntries;
  final List<_ProjectedShapeEntry> stateBoundaryEntries;
  final List<_ProjectedShapeEntry> timeZoneEntries;
  final Path landClipPath;
  final List<List<Offset>> projectedLandRings;
}

class _OverlayAnchorCache {
  const _OverlayAnchorCache({
    required this.projectedScene,
    required this.edgeRenderMode,
    required this.sourceMarkers,
    required this.sourceLabels,
    required this.markerPoints,
    required this.labelPoints,
  });

  final _ProjectedSceneCache projectedScene;
  final EdgeRenderMode edgeRenderMode;
  final List<PlaceMarker> sourceMarkers;
  final List<MapLabel> sourceLabels;
  final List<Offset> markerPoints;
  final List<Offset> labelPoints;
}

class _SelectedShapeTarget {
  const _SelectedShapeTarget({
    required this.name,
    required this.displayName,
    required this.role,
  });

  final String name;
  final String displayName;
  final String role;
}

enum _AstronomySelectionKind { star, constellation }

class _SelectedAstronomyTarget {
  const _SelectedAstronomyTarget({
    required this.id,
    required this.displayName,
    required this.kind,
  });

  final String id;
  final String displayName;
  final _AstronomySelectionKind kind;
}

class _WindTracePoint {
  const _WindTracePoint({
    required this.latitude,
    required this.longitude,
    required this.speedMps,
  });

  final double latitude;
  final double longitude;
  final double speedMps;
}

const Map<String, String> _zodiacGlyphs = <String, String>{
  'aries': '♈',
  'taurus': '♉',
  'gemini': '♊',
  'cancer': '♋',
  'leo': '♌',
  'virgo': '♍',
  'libra': '♎',
  'scorpius': '♏',
  'ophiuchus': '⛎',
  'sagittarius': '♐',
  'capricornus': '♑',
  'aquarius': '♒',
  'pisces': '♓',
};

String _selectionDisplayName(String value) {
  final multipartSuffix = RegExp(r'^(.*)\s+\d+$');
  final match = multipartSuffix.firstMatch(value.trim());
  if (match == null) {
    return value.trim();
  }
  final baseName = match.group(1)?.trim();
  return (baseName == null || baseName.isEmpty) ? value.trim() : baseName;
}

Offset _resolveDisplayPointForEdgeMode({
  required Offset originalPoint,
  required Path landClipPath,
  required List<List<Offset>> projectedLandRings,
  required EdgeRenderMode edgeRenderMode,
  required double viewScale,
  double maxSnapDistanceInScreen = 20,
}) {
  if (edgeRenderMode == EdgeRenderMode.country || projectedLandRings.isEmpty) {
    return originalPoint;
  }
  if (landClipPath.contains(originalPoint)) {
    return originalPoint;
  }

  final maxSnapDistance = maxSnapDistanceInScreen / viewScale.clamp(1.0, 24.0);
  final snappedPoint = _findNearestLandEdgePointForDisplay(
    originalPoint,
    projectedLandRings,
  );
  if (snappedPoint == null ||
      (snappedPoint - originalPoint).distance > maxSnapDistance) {
    return originalPoint;
  }
  return _insetPointInsideLandForDisplay(
    snappedPoint,
    originalPoint: originalPoint,
    landClipPath: landClipPath,
    viewScale: viewScale,
  );
}

Offset _insetPointInsideLandForDisplay(
  Offset snappedPoint, {
  required Offset originalPoint,
  required Path landClipPath,
  required double viewScale,
}) {
  if (landClipPath.contains(snappedPoint)) {
    return snappedPoint;
  }

  final fallbackDirections = <Offset>[
    Offset.zero - snappedPoint,
    originalPoint - snappedPoint,
    const Offset(0, -1),
    const Offset(1, 0),
    const Offset(0, 1),
    const Offset(-1, 0),
  ];
  final insetStep = 1.6 / viewScale.clamp(1.0, 24.0);
  const maxInsetSteps = 18;

  for (final direction in fallbackDirections) {
    final normalizedDirection = _normalizeOffsetForDisplay(direction);
    if (normalizedDirection == Offset.zero) {
      continue;
    }

    for (var step = 1; step <= maxInsetSteps; step += 1) {
      final candidate = snappedPoint +
          Offset(
            normalizedDirection.dx * insetStep * step,
            normalizedDirection.dy * insetStep * step,
          );
      if (landClipPath.contains(candidate)) {
        return candidate;
      }
    }
  }

  return snappedPoint;
}

Offset _normalizeOffsetForDisplay(Offset offset) {
  final distance = offset.distance;
  if (distance == 0) {
    return Offset.zero;
  }
  return Offset(offset.dx / distance, offset.dy / distance);
}

Offset? _findNearestLandEdgePointForDisplay(
  Offset point,
  List<List<Offset>> projectedLandRings,
) {
  Offset? nearestPoint;
  double? nearestDistance;

  for (final ring in projectedLandRings) {
    if (ring.length < 2) {
      continue;
    }
    for (var index = 0; index < ring.length; index += 1) {
      final start = ring[index];
      final end = ring[(index + 1) % ring.length];
      final candidate = _nearestPointOnSegmentForDisplay(point, start, end);
      final distance = (candidate - point).distanceSquared;
      if (nearestDistance == null || distance < nearestDistance) {
        nearestDistance = distance;
        nearestPoint = candidate;
      }
    }
  }

  return nearestPoint;
}

Offset _nearestPointOnSegmentForDisplay(
    Offset point, Offset start, Offset end) {
  final segment = end - start;
  final segmentLengthSquared =
      segment.dx * segment.dx + segment.dy * segment.dy;
  if (segmentLengthSquared == 0) {
    return start;
  }

  final projection = ((point.dx - start.dx) * segment.dx +
          (point.dy - start.dy) * segment.dy) /
      segmentLengthSquared;
  final t = projection.clamp(0.0, 1.0);
  return Offset(
    start.dx + segment.dx * t,
    start.dy + segment.dy * t,
  );
}

class FlatWorldCanvas extends StatefulWidget {
  const FlatWorldCanvas({
    super.key,
    required this.tileBaseUrl,
    required this.markers,
    required this.shapes,
    required this.labels,
    required this.showGrid,
    required this.showTimeZones,
    required this.useRealTimeZones,
    required this.gridStepDegrees,
    required this.edgeRenderMode,
    required this.showLabels,
    required this.showShapeLabels,
    required this.showStateBoundaries,
    required this.astronomySnapshot,
    required this.showSunPath,
    required this.showMoonPath,
    required this.showStars,
    required this.showConstellations,
    required this.showConstellationsFullSky,
    required this.windSnapshot,
    required this.showWindAnimation,
    required this.showWindOverlay,
    required this.weatherAnimationLabel,
    required this.weatherOverlaySnapshot,
    required this.showWeatherOverlay,
    required this.animateWind,
    required this.visiblePlanetNames,
    required this.astronomyObserverName,
    required this.routePoints,
    required this.activePickLabel,
    required this.onMapPointPicked,
    required this.onInteractionChanged,
    required this.onViewScaleChanged,
    required this.onVisibleMapBoundsChanged,
  });

  final String tileBaseUrl;
  final List<PlaceMarker> markers;
  final List<MapShape> shapes;
  final List<MapLabel> labels;
  final bool showGrid;
  final bool showTimeZones;
  final bool useRealTimeZones;
  final int gridStepDegrees;
  final EdgeRenderMode edgeRenderMode;
  final bool showLabels;
  final bool showShapeLabels;
  final bool showStateBoundaries;
  final AstronomySnapshot? astronomySnapshot;
  final bool showSunPath;
  final bool showMoonPath;
  final bool showStars;
  final bool showConstellations;
  final bool showConstellationsFullSky;
  final WindSnapshot? windSnapshot;
  final bool showWindAnimation;
  final bool showWindOverlay;
  final String weatherAnimationLabel;
  final WeatherOverlaySnapshot? weatherOverlaySnapshot;
  final bool showWeatherOverlay;
  final bool animateWind;
  final List<String> visiblePlanetNames;
  final String? astronomyObserverName;
  final List<PlaceMarker?> routePoints;
  final String? activePickLabel;
  final ValueChanged<MapTapLocation>? onMapPointPicked;
  final ValueChanged<bool>? onInteractionChanged;
  final ValueChanged<double>? onViewScaleChanged;
  final ValueChanged<Rect>? onVisibleMapBoundsChanged;

  @override
  State<FlatWorldCanvas> createState() => _FlatWorldCanvasState();
}

class _FlatWorldCanvasState extends State<FlatWorldCanvas>
    with TickerProviderStateMixin {
  static const double _maxScale = 24;
  final TransformationController _transformationController =
      TransformationController();
  late final AnimationController _astronomyAnimationController;
  late final AnimationController _astronomyTransitionController;
  Timer? _interactionEndTimer;
  double _rotationRadians = 0;
  double _labelScale = 1;
  double _viewScale = 1;
  Offset _lastViewTranslation = Offset.zero;
  _GridHoverData? _hoveredGridPoint;
  bool _isInteracting = false;
  final Set<String> _prefetchedTileKeys = <String>{};
  Size? _cachedSceneSize;
  Size? _latestViewportSize;
  _ProjectedSceneCache? _projectedSceneCache;
  _OverlayAnchorCache? _overlayAnchorCache;
  AstronomySnapshot? _previousAstronomySnapshot;
  SkyCatalog? _skyCatalog;
  bool _hasInitializedView = false;
  _SelectedShapeTarget? _selectedShape;
  _SelectedAstronomyTarget? _selectedAstronomyTarget;

  bool get _shouldAnimateAstronomy =>
      (widget.astronomySnapshot != null &&
          (widget.showSunPath ||
              widget.showMoonPath ||
              widget.visiblePlanetNames.isNotEmpty)) ||
      (widget.showWindAnimation &&
          widget.animateWind &&
          widget.windSnapshot != null);

  @override
  void initState() {
    super.initState();
    _astronomyAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    _astronomyTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1,
    );
    _transformationController.addListener(_handleTransformChanged);
    final initialMatrix = _transformationController.value;
    _lastViewTranslation = Offset(
      initialMatrix.storage[12],
      initialMatrix.storage[13],
    );
    _loadSkyCatalog();
    _syncAstronomyAnimation();
  }

  Future<void> _loadSkyCatalog() async {
    try {
      final loadedCatalog = await SkyCatalogLoader.instance.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _skyCatalog = loadedCatalog;
      });
    } catch (_) {
      // Keep the astronomy overlay functional even if the local catalog fails.
    }
  }

  @override
  void didUpdateWidget(covariant FlatWorldCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.shapes, widget.shapes)) {
      _cachedSceneSize = null;
      _overlayAnchorCache = null;
      _selectedShape = null;
    }
    if (oldWidget.astronomySnapshot != widget.astronomySnapshot &&
        oldWidget.astronomySnapshot != null &&
        widget.astronomySnapshot != null) {
      _previousAstronomySnapshot = oldWidget.astronomySnapshot;
      _astronomyTransitionController.forward(from: 0);
    } else if (widget.astronomySnapshot == null) {
      _previousAstronomySnapshot = null;
      _astronomyTransitionController.value = 1;
      _selectedAstronomyTarget = null;
    }
    _syncAstronomyAnimation();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedWidth ||
              !constraints.hasBoundedHeight ||
              !constraints.maxWidth.isFinite ||
              !constraints.maxHeight.isFinite ||
              constraints.maxWidth <= 0 ||
              constraints.maxHeight <= 0) {
            return const SizedBox.expand();
          }

          _latestViewportSize = constraints.biggest;
          if (!_hasInitializedView) {
            _hasInitializedView = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _latestViewportSize == null) {
                return;
              }
              _applyDefaultView(_latestViewportSize!);
            });
          }

          final isCompactViewport = constraints.maxWidth < 560;
          final projectedScene = _ensureProjectedSceneCache(
            constraints.biggest,
          );
          final overlayAnchors = _ensureOverlayAnchorCache(projectedScene);
          final hasTileBase = widget.shapes.isNotEmpty;
          final tileZoom = _tileZoomForViewScale(_viewScale);
          final visibleSceneRect = _visibleSceneRect(constraints.biggest);
          final tileRange = _visibleTileRange(
            viewportSize: constraints.biggest,
            visibleSceneRect: visibleSceneRect,
            tileZoom: tileZoom,
          );
          if (hasTileBase && !_isInteracting) {
            _scheduleTilePrefetch(
              context: context,
              isCompactViewport: isCompactViewport,
              tileZoom: tileZoom,
              tileRange: tileRange,
            );
          }
          return Stack(
            children: [
              MouseRegion(
                onExit: (_) {
                  if (_hoveredGridPoint != null && mounted) {
                    setState(() {
                      _hoveredGridPoint = null;
                    });
                  }
                },
                onHover: (event) {
                  final hovered = widget.showGrid
                      ? _resolveHoveredGridIntersection(
                          event.localPosition,
                          constraints.biggest,
                        )
                      : null;
                  final isSameHover = hovered != null &&
                      _hoveredGridPoint != null &&
                      hovered.latitude == _hoveredGridPoint!.latitude &&
                      hovered.longitude == _hoveredGridPoint!.longitude &&
                      (hovered.anchor - _hoveredGridPoint!.anchor).distance < 8;
                  if (mounted &&
                      !isSameHover &&
                      (hovered != null || _hoveredGridPoint != null)) {
                    setState(() {
                      _hoveredGridPoint = hovered;
                    });
                  }
                },
                child: Listener(
                  onPointerSignal: (pointerSignal) {
                    if (pointerSignal is PointerScrollEvent) {
                      _handleScrollZoom(
                        pointerSignal.localPosition,
                        pointerSignal.scrollDelta.dy,
                      );
                    }
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.deferToChild,
                    onTapUp: widget.activePickLabel == null
                        ? (details) => _handleCanvasTap(
                              details.localPosition,
                              projectedScene,
                            )
                        : null,
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      boundaryMargin: const EdgeInsets.all(240),
                      minScale: _minScaleForViewport(constraints.biggest),
                      maxScale: _maxScale,
                      onInteractionStart: (_) => _beginInteraction(),
                      onInteractionEnd: (_) => _scheduleInteractionEnd(),
                      panEnabled: true,
                      scaleEnabled: true,
                      trackpadScrollCausesScale: true,
                      child: RepaintBoundary(
                        child: SizedBox(
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (hasTileBase)
                                RepaintBoundary(
                                  child: ClipPath(
                                    clipper: const _MapDiskClipper(),
                                    child: _MapTileLayer(
                                      baseUrl: widget.tileBaseUrl,
                                      edgeMode: widget.edgeRenderMode,
                                      tileVersion: _tileCacheVersion,
                                      viewportSize: constraints.biggest,
                                      tileZoom: tileZoom,
                                      tileRange: tileRange,
                                      showParentFallback:
                                          !isCompactViewport && !_isInteracting,
                                    ),
                                  ),
                                ),
                              if (!hasTileBase)
                                RepaintBoundary(
                                  child: CustomPaint(
                                    isComplex: true,
                                    willChange: false,
                                    painter: _BaseMapPainter(
                                      projectedScene: projectedScene,
                                      edgeRenderMode: widget.edgeRenderMode,
                                    ),
                                  ),
                                ),
                              RepaintBoundary(
                                child: CustomPaint(
                                  painter: _FlatWorldPainter(
                                    repaint: Listenable.merge([
                                      _astronomyAnimationController,
                                      _astronomyTransitionController,
                                    ]),
                                    projectedScene: projectedScene,
                                    visibleSceneRect: visibleSceneRect,
                                    selectedShape: _selectedShape,
                                    selectedAstronomy: _selectedAstronomyTarget,
                                    markerAnchorPoints:
                                        overlayAnchors.markerPoints,
                                    labelAnchorPoints:
                                        overlayAnchors.labelPoints,
                                    markers: widget.markers,
                                    labels: widget.labels,
                                    showGrid: widget.showGrid,
                                    showTimeZones: widget.showTimeZones,
                                    useRealTimeZones: widget.useRealTimeZones,
                                    gridStepDegrees: widget.gridStepDegrees,
                                    edgeRenderMode: widget.edgeRenderMode,
                                    showLabels: widget.showLabels,
                                    showShapeLabels: widget.showShapeLabels,
                                    showStateBoundaries:
                                        widget.showStateBoundaries,
                                    previousAstronomySnapshot:
                                        _previousAstronomySnapshot,
                                    astronomySnapshot: widget.astronomySnapshot,
                                    skyCatalog: _skyCatalog,
                                    astronomyTransitionAnimation:
                                        _astronomyTransitionController,
                                    showSunPath: widget.showSunPath,
                                    showMoonPath: widget.showMoonPath,
                                    showStars: widget.showStars,
                                    showConstellations:
                                        widget.showConstellations,
                                    showConstellationsFullSky:
                                        widget.showConstellationsFullSky,
                                    windSnapshot: widget.windSnapshot,
                                    showWindAnimation: widget.showWindAnimation,
                                    showWindOverlay: widget.showWindOverlay,
                                    weatherAnimationLabel:
                                        widget.weatherAnimationLabel,
                                    weatherOverlaySnapshot:
                                        widget.weatherOverlaySnapshot,
                                    showWeatherOverlay:
                                        widget.showWeatherOverlay,
                                    animateWind: widget.animateWind,
                                    visiblePlanetNames:
                                        widget.visiblePlanetNames,
                                    astronomyObserverName:
                                        widget.astronomyObserverName,
                                    routePoints: widget.routePoints,
                                    labelScale: _labelScale,
                                    viewScale: _viewScale,
                                    viewRotationRadians: _rotationRadians,
                                    astronomyPulseAnimation:
                                        _astronomyAnimationController,
                                    isInteracting: _isInteracting,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.activePickLabel != null)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapUp: (details) {
                      final selection = _resolveTapLocation(
                        details.localPosition,
                        constraints.biggest,
                      );
                      if (selection != null) {
                        widget.onMapPointPicked?.call(selection);
                      }
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0x180A2233),
                        border: Border.all(
                          color: const Color(0xAAF8F2DE),
                          width: 1.5,
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          margin: const EdgeInsets.only(top: 18),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xE6112A46),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Click map to set point ${widget.activePickLabel}',
                            style: const TextStyle(
                              color: Color(0xFFF8F3E8),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: isCompactViewport ? 10 : 14,
                right: 14,
                child: _ZoomControls(
                  compact: isCompactViewport,
                  onZoomIn: () => _zoomAtCenter(1.35),
                  onZoomOut: () => _zoomAtCenter(1 / 1.35),
                  onRotateLeft: () => _rotateAtCenter(
                    -math.pi / 12,
                    constraints.biggest.center(Offset.zero),
                  ),
                  onRotateRight: () => _rotateAtCenter(
                    math.pi / 12,
                    constraints.biggest.center(Offset.zero),
                  ),
                  onReset: _resetView,
                ),
              ),
              if (widget.showGrid && _hoveredGridPoint != null)
                Positioned(
                  left: (_hoveredGridPoint!.anchor.dx + 14)
                      .clamp(12.0, math.max(12.0, constraints.maxWidth - 126.0))
                      .toDouble(),
                  top: (_hoveredGridPoint!.anchor.dy - 44)
                      .clamp(12.0, math.max(12.0, constraints.maxHeight - 56.0))
                      .toDouble(),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xE6112A46),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x26000000),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        child: Text(
                          '${_formatLatitudeLabel(_hoveredGridPoint!.latitude)}, ${_formatLongitudeLabel(_hoveredGridPoint!.longitude)}',
                          style: const TextStyle(
                            color: Color(0xFFF8F3E8),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  _ProjectedSceneCache _ensureProjectedSceneCache(Size size) {
    final hasMatchingCache = _projectedSceneCache != null &&
        _cachedSceneSize == size &&
        identical(_projectedSceneCache!.sourceShapes, widget.shapes);
    if (hasMatchingCache) {
      return _projectedSceneCache!;
    }

    final nextCache = _buildProjectedSceneCache(size, widget.shapes);
    _projectedSceneCache = nextCache;
    _cachedSceneSize = size;
    return nextCache;
  }

  _OverlayAnchorCache _ensureOverlayAnchorCache(
      _ProjectedSceneCache projectedScene) {
    final hasMatchingCache = _overlayAnchorCache != null &&
        identical(_overlayAnchorCache!.projectedScene, projectedScene) &&
        _overlayAnchorCache!.edgeRenderMode == widget.edgeRenderMode &&
        identical(_overlayAnchorCache!.sourceMarkers, widget.markers) &&
        identical(_overlayAnchorCache!.sourceLabels, widget.labels);
    if (hasMatchingCache) {
      return _overlayAnchorCache!;
    }

    final markerPoints = widget.markers.map((marker) {
      final originalPoint = _projectMapPoint(
        projectedScene.center,
        projectedScene.mapRadius,
        marker.x,
        marker.y,
      );
      if (marker.latitude >= 89.999) {
        return originalPoint;
      }
      return _resolveDisplayPointForEdgeMode(
        originalPoint: originalPoint,
        landClipPath: projectedScene.landClipPath,
        projectedLandRings: projectedScene.projectedLandRings,
        edgeRenderMode: widget.edgeRenderMode,
        viewScale: 1,
        maxSnapDistanceInScreen: marker.zone == 'antarctic_ring' ? 16 : 28,
      );
    }).toList(growable: false);

    final labelPoints = widget.labels.map((label) {
      final originalPoint = _projectMapPoint(
        projectedScene.center,
        projectedScene.mapRadius,
        label.x,
        label.y,
      );
      return _resolveDisplayPointForEdgeMode(
        originalPoint: originalPoint,
        landClipPath: projectedScene.landClipPath,
        projectedLandRings: projectedScene.projectedLandRings,
        edgeRenderMode: widget.edgeRenderMode,
        viewScale: 1,
        maxSnapDistanceInScreen: _isPointLabelLayer(label.layer) ? 44 : 26,
      );
    }).toList(growable: false);

    _overlayAnchorCache = _OverlayAnchorCache(
      projectedScene: projectedScene,
      edgeRenderMode: widget.edgeRenderMode,
      sourceMarkers: widget.markers,
      sourceLabels: widget.labels,
      markerPoints: markerPoints,
      labelPoints: labelPoints,
    );
    return _overlayAnchorCache!;
  }

  int _tileZoomForViewScale(double viewScale) {
    final rawZoom =
        (math.log(viewScale.clamp(1.0, 24.0)) / math.ln2).floor() + 2;
    return rawZoom.clamp(0, 6).toInt();
  }

  Rect _visibleSceneRect(Size viewportSize) {
    final sceneTopLeft = _transformationController.toScene(Offset.zero);
    final sceneTopRight = _transformationController.toScene(
      Offset(viewportSize.width, 0),
    );
    final sceneBottomLeft = _transformationController.toScene(
      Offset(0, viewportSize.height),
    );
    final sceneBottomRight = _transformationController.toScene(
      Offset(viewportSize.width, viewportSize.height),
    );
    final left = [
      sceneTopLeft.dx,
      sceneTopRight.dx,
      sceneBottomLeft.dx,
      sceneBottomRight.dx,
    ].reduce(math.min);
    final right = [
      sceneTopLeft.dx,
      sceneTopRight.dx,
      sceneBottomLeft.dx,
      sceneBottomRight.dx,
    ].reduce(math.max);
    final top = [
      sceneTopLeft.dy,
      sceneTopRight.dy,
      sceneBottomLeft.dy,
      sceneBottomRight.dy,
    ].reduce(math.min);
    final bottom = [
      sceneTopLeft.dy,
      sceneTopRight.dy,
      sceneBottomLeft.dy,
      sceneBottomRight.dy,
    ].reduce(math.max);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Rect _visibleMapRect(Size viewportSize) {
    final sceneTopLeft = _transformationController.toScene(Offset.zero);
    final sceneTopRight = _transformationController.toScene(
      Offset(viewportSize.width, 0),
    );
    final sceneBottomLeft = _transformationController.toScene(
      Offset(0, viewportSize.height),
    );
    final sceneBottomRight = _transformationController.toScene(
      Offset(viewportSize.width, viewportSize.height),
    );
    final center = viewportSize.center(Offset.zero);
    final mapRadius = (math.min(viewportSize.width, viewportSize.height) / 2) *
        _mapRadiusScaleForSize(viewportSize);
    final visibleCorners = [
      sceneTopLeft,
      sceneTopRight,
      sceneBottomLeft,
      sceneBottomRight,
    ]
        .map(
          (point) => Offset(
            (point.dx - center.dx) / mapRadius,
            (point.dy - center.dy) / mapRadius,
          ),
        )
        .toList(growable: false);
    final left = visibleCorners.map((point) => point.dx).reduce(math.min);
    final right = visibleCorners.map((point) => point.dx).reduce(math.max);
    final top = visibleCorners.map((point) => point.dy).reduce(math.min);
    final bottom = visibleCorners.map((point) => point.dy).reduce(math.max);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  _TileRange _visibleTileRange({
    required Size viewportSize,
    required Rect visibleSceneRect,
    required int tileZoom,
  }) {
    if (!viewportSize.width.isFinite ||
        !viewportSize.height.isFinite ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0) {
      return const _TileRange(minX: 0, maxX: 0, minY: 0, maxY: 0);
    }

    final tileCount = 1 << tileZoom;
    final tileWidth = viewportSize.width / tileCount;
    final tileHeight = viewportSize.height / tileCount;
    final minX = (visibleSceneRect.left / tileWidth)
        .floor()
        .clamp(0, tileCount - 1)
        .toInt();
    final maxX = (visibleSceneRect.right / tileWidth)
        .ceil()
        .clamp(0, tileCount - 1)
        .toInt();
    final minY = (visibleSceneRect.top / tileHeight)
        .floor()
        .clamp(0, tileCount - 1)
        .toInt();
    final maxY = (visibleSceneRect.bottom / tileHeight)
        .ceil()
        .clamp(0, tileCount - 1)
        .toInt();
    return _TileRange(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
    );
  }

  void _scheduleTilePrefetch({
    required BuildContext context,
    required bool isCompactViewport,
    required int tileZoom,
    required _TileRange tileRange,
  }) {
    if (isCompactViewport || _isInteracting) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final tileCount = 1 << tileZoom;
      final edgeMode = _edgeModeSlug(widget.edgeRenderMode);
      final minX = (tileRange.minX - 1).clamp(0, tileCount - 1).toInt();
      final maxX = (tileRange.maxX + 1).clamp(0, tileCount - 1).toInt();
      final minY = (tileRange.minY - 1).clamp(0, tileCount - 1).toInt();
      final maxY = (tileRange.maxY + 1).clamp(0, tileCount - 1).toInt();
      for (var tileX = minX; tileX <= maxX; tileX += 1) {
        for (var tileY = minY; tileY <= maxY; tileY += 1) {
          final isVisibleTile = tileX >= tileRange.minX &&
              tileX <= tileRange.maxX &&
              tileY >= tileRange.minY &&
              tileY <= tileRange.maxY;
          if (isVisibleTile) {
            continue;
          }
          final key = '$_sharedTileSet:$edgeMode:$tileZoom:$tileX:$tileY';
          if (_prefetchedTileKeys.contains(key)) {
            continue;
          }
          _prefetchedTileKeys.add(key);
          unawaited(
            precacheImage(
              NetworkImage(
                '${widget.tileBaseUrl}/map/tiles/$edgeMode/$tileZoom/$tileX/$tileY.png?v=$_tileCacheVersion',
              ),
              context,
              onError: (_, __) {},
            ),
          );
        }
      }
    });
  }

  _ProjectedSceneCache _buildProjectedSceneCache(
    Size size,
    List<MapShape> shapes,
  ) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final mapRadius = radius * _mapRadiusScaleForSize(size);
    final landEntries = <_ProjectedShapeEntry>[];
    final boundaryEntries = <_ProjectedShapeEntry>[];
    final stateBoundaryEntries = <_ProjectedShapeEntry>[];
    final timeZoneEntries = <_ProjectedShapeEntry>[];
    final landClipPath = Path()..fillType = PathFillType.evenOdd;
    final projectedLandRings = <List<Offset>>[];

    for (final shape in shapes) {
      final rings =
          shape.rings.where((ring) => ring.points.isNotEmpty).toList();
      if (rings.isEmpty) {
        continue;
      }

      final path = _buildProjectedShapePath(rings, center, mapRadius);
      final hasClosedRing = rings.any((ring) => ring.closed);
      final entry = _ProjectedShapeEntry(
        shape: shape,
        path: path,
        bounds: path.getBounds(),
        hasClosedRing: hasClosedRing,
      );

      if (shape.role == 'boundary') {
        boundaryEntries.add(entry);
        continue;
      }
      if (shape.role == 'state_boundary') {
        stateBoundaryEntries.add(entry);
        continue;
      }
      if (shape.role == 'timezone') {
        timeZoneEntries.add(entry);
        continue;
      }

      landEntries.add(entry);
      if (!hasClosedRing) {
        continue;
      }
      landClipPath.addPath(path, Offset.zero);
      for (final ring in rings.where((ring) => ring.closed)) {
        projectedLandRings.add(_projectMapRing(center, mapRadius, ring));
      }
    }

    return _ProjectedSceneCache(
      size: size,
      center: center,
      radius: radius,
      mapRadius: mapRadius,
      sourceShapes: shapes,
      landEntries: landEntries,
      boundaryEntries: boundaryEntries,
      stateBoundaryEntries: stateBoundaryEntries,
      timeZoneEntries: timeZoneEntries,
      landClipPath: landClipPath,
      projectedLandRings: projectedLandRings,
    );
  }

  void _handleScrollZoom(Offset focalPoint, double scrollDelta) {
    _beginInteraction();
    final currentMatrix = _transformationController.value.clone();
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    final minScale = _minScaleForViewport(_latestViewportSize);
    final scaleDelta = scrollDelta < 0 ? 1.1 : 0.9;
    final targetScale = (currentScale * scaleDelta).clamp(minScale, _maxScale);
    final appliedScale = targetScale / currentScale;
    if (appliedScale == 1) {
      return;
    }

    final nextMatrix = currentMatrix
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(appliedScale, appliedScale, 1, 1)
      ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0, 1);

    _transformationController.value = nextMatrix;
    _scheduleInteractionEnd();
  }

  void _zoomAtCenter(double scaleDelta) {
    _beginInteraction();
    final currentMatrix = _transformationController.value.clone();
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    final minScale = _minScaleForViewport(_latestViewportSize);
    final targetScale = (currentScale * scaleDelta).clamp(minScale, _maxScale);
    final appliedScale = targetScale / currentScale;
    if (appliedScale == 1) {
      return;
    }

    final nextMatrix = currentMatrix
      ..scaleByDouble(appliedScale, appliedScale, 1, 1);
    _transformationController.value = nextMatrix;
    _scheduleInteractionEnd();
  }

  void _rotateAtCenter(double angleRadians, Offset focalPoint) {
    _beginInteraction();
    final currentMatrix = _transformationController.value.clone();
    final nextMatrix = currentMatrix
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..rotateZ(angleRadians)
      ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0, 1);

    setState(() {
      _rotationRadians += angleRadians;
      _transformationController.value = nextMatrix;
    });
    _scheduleInteractionEnd();
  }

  void _resetView() {
    _beginInteraction();
    final viewportSize = _latestViewportSize;
    if (viewportSize == null) {
      setState(() {
        _rotationRadians = 0;
        _labelScale = 1;
        _viewScale = 1;
        _transformationController.value = Matrix4.identity();
      });
    } else {
      _applyDefaultView(viewportSize);
    }
    _scheduleInteractionEnd();
  }

  double _minScaleForViewport(Size? viewportSize) {
    if (viewportSize == null) {
      return 1;
    }
    return viewportSize.width < 560 ? 0.82 : 0.96;
  }

  double _defaultScaleForViewport(Size viewportSize) {
    return viewportSize.width < 560 ? 0.88 : 0.97;
  }

  void _applyDefaultView(Size viewportSize) {
    final scale = _defaultScaleForViewport(viewportSize);
    final horizontalInset = (viewportSize.width * (1 - scale)) / 2;
    final verticalInset = (viewportSize.height * (1 - scale)) / 2;
    setState(() {
      _rotationRadians = 0;
      _labelScale = scale;
      _viewScale = scale;
      _transformationController.value = Matrix4.identity()
        ..translateByDouble(horizontalInset, verticalInset, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);
    });
    final currentMatrix = _transformationController.value;
    _lastViewTranslation = Offset(
      currentMatrix.storage[12],
      currentMatrix.storage[13],
    );
    widget.onViewScaleChanged?.call(scale);
    widget.onVisibleMapBoundsChanged?.call(_visibleMapRect(viewportSize));
  }

  void _beginInteraction() {
    _interactionEndTimer?.cancel();
    if (_isInteracting) {
      return;
    }
    _isInteracting = true;
    widget.onInteractionChanged?.call(true);
  }

  void _scheduleInteractionEnd() {
    _interactionEndTimer?.cancel();
    _interactionEndTimer = Timer(
      const Duration(milliseconds: 220),
      () {
        if (!_isInteracting) {
          return;
        }
        _isInteracting = false;
        widget.onInteractionChanged?.call(false);
      },
    );
  }

  void _handleTransformChanged() {
    final matrix = _transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translation = Offset(matrix.storage[12], matrix.storage[13]);
    final shouldRebuild = (scale - _labelScale).abs() > 0.04 ||
        (scale - _viewScale).abs() > 0.04 ||
        (translation - _lastViewTranslation).distance > 8;
    if (shouldRebuild && mounted) {
      setState(() {
        _labelScale = scale;
        _viewScale = scale;
        _lastViewTranslation = translation;
      });
      widget.onViewScaleChanged?.call(scale);
      final viewportSize = _latestViewportSize;
      if (viewportSize != null) {
        widget.onVisibleMapBoundsChanged?.call(_visibleMapRect(viewportSize));
      }
    }
  }

  _GridHoverData? _resolveHoveredGridIntersection(
    Offset viewportPosition,
    Size canvasSize,
  ) {
    final scenePoint = _transformationController.toScene(viewportPosition);
    final center = canvasSize.center(Offset.zero);
    final radius = math.min(canvasSize.width, canvasSize.height) / 2;
    final mapRadius = radius * _mapRadiusScaleForSize(canvasSize);
    final normalizedX = (scenePoint.dx - center.dx) / mapRadius;
    final normalizedY = (scenePoint.dy - center.dy) / mapRadius;
    final radiusRatio = math.sqrt(
      normalizedX * normalizedX + normalizedY * normalizedY,
    );
    if (radiusRatio > 1) {
      return null;
    }

    final thetaDegrees =
        (math.atan2(normalizedY, normalizedX) * 180 / math.pi + 360) % 360;
    final rawLongitude = ((-thetaDegrees - 90 + 540) % 360) - 180;
    final latitude = radiusRatio <= _innerWorldRadius
        ? 90 - (radiusRatio / _innerWorldRadius) * (90 - _innerWorldMinLatitude)
        : _innerWorldMinLatitude -
            ((radiusRatio - _innerWorldRadius) /
                    (_outerRingRadius - _innerWorldRadius)) *
                30;

    final candidateLatitudes = _buildLatitudeGridValues(widget.gridStepDegrees);
    final snappedLatitude = candidateLatitudes.reduce(
      (best, current) =>
          (latitude - current).abs() < (latitude - best).abs() ? current : best,
    );
    final candidateLongitudes =
        _buildLongitudeGridValues(widget.gridStepDegrees);
    final snappedLongitude = candidateLongitudes.reduce(
      (best, current) =>
          _longitudeDistanceDegrees(rawLongitude, current.toDouble()) <
                  _longitudeDistanceDegrees(rawLongitude, best.toDouble())
              ? current
              : best,
    );

    final intersectionRadius = _latitudeToRadiusRatio(snappedLatitude);
    final theta = _longitudeToThetaRadians(snappedLongitude.toDouble());
    final intersectionScenePoint = Offset(
      center.dx + math.cos(theta) * mapRadius * intersectionRadius,
      center.dy + math.sin(theta) * mapRadius * intersectionRadius,
    );
    final maxDistanceInScene = 12 / _viewScale.clamp(1.0, 8.0);
    if ((scenePoint - intersectionScenePoint).distance > maxDistanceInScene) {
      return null;
    }

    return _GridHoverData(
      latitude: snappedLatitude,
      longitude: snappedLongitude,
      anchor: viewportPosition,
    );
  }

  void _handleCanvasTap(
    Offset viewportPosition,
    _ProjectedSceneCache projectedScene,
  ) {
    final nextAstronomySelection = _resolveAstronomySelection(
      viewportPosition,
      projectedScene,
    );
    final nextSelection = nextAstronomySelection == null
        ? _resolveShapeSelection(
            viewportPosition,
            projectedScene,
          )
        : null;
    setState(() {
      _selectedAstronomyTarget = nextAstronomySelection;
      _selectedShape = nextSelection;
    });
  }

  _SelectedAstronomyTarget? _resolveAstronomySelection(
    Offset viewportPosition,
    _ProjectedSceneCache projectedScene,
  ) {
    final snapshot = widget.astronomySnapshot;
    final catalog = _skyCatalog;
    if (snapshot == null || catalog == null) {
      return null;
    }

    final scenePoint = _transformationController.toScene(viewportPosition);
    final astronomyHitDistance = 18 / _viewScale.clamp(1.0, 24.0);

    if (widget.showConstellations) {
      _SelectedAstronomyTarget? bestConstellation;
      double? bestDistance;
      const labelVerticalOffset = Offset(0, -12);
      for (final constellation in catalog.constellations) {
        final labelLongitude = _skyLongitudeDegrees(
          constellation.labelRightAscensionHours,
          snapshot.greenwichSiderealDegrees,
        );
        final labelVisibility = _nightSkyVisibility(
          snapshot,
          latitude: constellation.labelDeclinationDegrees,
          longitude: labelLongitude,
          forceVisible: widget.showConstellationsFullSky,
        );
        final labelPoint = _projectSkyCoordinatePoint(
              projectedScene.center,
              projectedScene.mapRadius,
              rightAscensionHours: constellation.labelRightAscensionHours,
              declinationDegrees: constellation.labelDeclinationDegrees,
              siderealDegrees: snapshot.greenwichSiderealDegrees,
            ) +
            _screenOffsetToScene(labelVerticalOffset, _viewScale);
        final labelDistance = (scenePoint - labelPoint).distance;
        if (labelVisibility > 0.08 &&
            labelDistance <= astronomyHitDistance * 1.4 &&
            (bestDistance == null || labelDistance < bestDistance)) {
          bestConstellation = _SelectedAstronomyTarget(
            id: constellation.id,
            displayName: constellation.name,
            kind: _AstronomySelectionKind.constellation,
          );
          bestDistance = labelDistance;
        }

        for (final segment in constellation.segments) {
          if (segment.length != 2) {
            continue;
          }
          final startStar = catalog.starsById[segment[0]];
          final endStar = catalog.starsById[segment[1]];
          if (startStar == null || endStar == null) {
            continue;
          }
          final startLongitude = _skyLongitudeDegrees(
            startStar.rightAscensionHours,
            snapshot.greenwichSiderealDegrees,
          );
          final endLongitude = _skyLongitudeDegrees(
            endStar.rightAscensionHours,
            snapshot.greenwichSiderealDegrees,
          );
          final segmentVisibility = ((_nightSkyVisibility(
                        snapshot,
                        latitude: startStar.declinationDegrees,
                        longitude: startLongitude,
                        forceVisible: widget.showConstellationsFullSky,
                      ) +
                      _nightSkyVisibility(
                        snapshot,
                        latitude: endStar.declinationDegrees,
                        longitude: endLongitude,
                        forceVisible: widget.showConstellationsFullSky,
                      )) /
                  2)
              .toDouble();
          if (segmentVisibility <= 0.04) {
            continue;
          }
          final startPoint = _projectSkyCoordinatePoint(
            projectedScene.center,
            projectedScene.mapRadius,
            rightAscensionHours: startStar.rightAscensionHours,
            declinationDegrees: startStar.declinationDegrees,
            siderealDegrees: snapshot.greenwichSiderealDegrees,
          );
          final endPoint = _projectSkyCoordinatePoint(
            projectedScene.center,
            projectedScene.mapRadius,
            rightAscensionHours: endStar.rightAscensionHours,
            declinationDegrees: endStar.declinationDegrees,
            siderealDegrees: snapshot.greenwichSiderealDegrees,
          );
          final nearestPoint = _nearestPointOnSegmentForDisplay(
            scenePoint,
            startPoint,
            endPoint,
          );
          final segmentDistance = (scenePoint - nearestPoint).distance;
          if (segmentDistance <= astronomyHitDistance &&
              (bestDistance == null || segmentDistance < bestDistance)) {
            bestConstellation = _SelectedAstronomyTarget(
              id: constellation.id,
              displayName: constellation.name,
              kind: _AstronomySelectionKind.constellation,
            );
            bestDistance = segmentDistance;
          }
        }
      }
      if (bestConstellation != null) {
        return bestConstellation;
      }
    }

    if (widget.showStars) {
      _SelectedAstronomyTarget? bestStar;
      double? bestDistance;
      for (final star in catalog.stars) {
        final starPoint = _projectSkyCoordinatePoint(
          projectedScene.center,
          projectedScene.mapRadius,
          rightAscensionHours: star.rightAscensionHours,
          declinationDegrees: star.declinationDegrees,
          siderealDegrees: snapshot.greenwichSiderealDegrees,
        );
        final distance = (scenePoint - starPoint).distance;
        if (distance > astronomyHitDistance) {
          continue;
        }
        if (bestDistance == null || distance < bestDistance) {
          bestStar = _SelectedAstronomyTarget(
            id: star.id,
            displayName: star.name,
            kind: _AstronomySelectionKind.star,
          );
          bestDistance = distance;
        }
      }
      if (bestStar != null) {
        return bestStar;
      }
    }

    return null;
  }

  _SelectedShapeTarget? _resolveShapeSelection(
    Offset viewportPosition,
    _ProjectedSceneCache projectedScene,
  ) {
    final scenePoint = _transformationController.toScene(viewportPosition);
    if (!projectedScene.landClipPath.contains(scenePoint)) {
      return null;
    }

    if (widget.showStateBoundaries) {
      final selectedState = _findShapeAtScenePoint(
        projectedScene.stateBoundaryEntries,
        scenePoint,
        role: 'state_boundary',
      );
      if (selectedState != null) {
        return selectedState;
      }
    }

    return _findShapeAtScenePoint(
      projectedScene.boundaryEntries,
      scenePoint,
      role: 'boundary',
    );
  }

  _SelectedShapeTarget? _findShapeAtScenePoint(
    List<_ProjectedShapeEntry> entries,
    Offset scenePoint, {
    required String role,
  }) {
    _ProjectedShapeEntry? selectedEntry;
    double? selectedArea;
    for (final entry in entries) {
      if (!entry.hasClosedRing ||
          !entry.bounds.inflate(2).contains(scenePoint)) {
        continue;
      }
      if (!entry.path.contains(scenePoint)) {
        continue;
      }
      final area = entry.bounds.width * entry.bounds.height;
      if (selectedArea == null || area < selectedArea) {
        selectedEntry = entry;
        selectedArea = area;
      }
    }

    if (selectedEntry == null) {
      return null;
    }

    return _SelectedShapeTarget(
      name: _selectionDisplayName(selectedEntry.shape.name),
      displayName: _selectionDisplayName(selectedEntry.shape.name),
      role: role,
    );
  }

  MapTapLocation? _resolveTapLocation(
      Offset viewportPosition, Size canvasSize) {
    final scenePoint = _transformationController.toScene(viewportPosition);
    final center = canvasSize.center(Offset.zero);
    final radius = math.min(canvasSize.width, canvasSize.height) / 2;
    final mapRadius = radius * _mapRadiusScaleForSize(canvasSize);
    final normalizedX = (scenePoint.dx - center.dx) / mapRadius;
    final normalizedY = (scenePoint.dy - center.dy) / mapRadius;
    final radiusRatio = math.sqrt(
      normalizedX * normalizedX + normalizedY * normalizedY,
    );

    if (radiusRatio > 1) {
      return null;
    }

    final thetaDegrees =
        (math.atan2(normalizedY, normalizedX) * 180 / math.pi + 360) % 360;
    final rawLongitude = ((-thetaDegrees - 90 + 540) % 360) - 180;

    final latitude = radiusRatio <= _innerWorldRadius
        ? 90 - (radiusRatio / _innerWorldRadius) * (90 - _innerWorldMinLatitude)
        : _innerWorldMinLatitude -
            ((radiusRatio - _innerWorldRadius) /
                    (_outerRingRadius - _innerWorldRadius)) *
                30;

    return MapTapLocation(
      latitude: latitude.clamp(-90, 90).toDouble(),
      longitude: rawLongitude.clamp(-180, 180).toDouble(),
      x: normalizedX,
      y: normalizedY,
      zone: radiusRatio <= _innerWorldRadius ? 'inner_world' : 'antarctic_ring',
    );
  }

  void _syncAstronomyAnimation() {
    if (_shouldAnimateAstronomy) {
      if (!_astronomyAnimationController.isAnimating) {
        _astronomyAnimationController.repeat();
      }
      return;
    }

    if (_astronomyAnimationController.isAnimating) {
      _astronomyAnimationController.stop();
    }
    if (_astronomyAnimationController.value != 0) {
      _astronomyAnimationController.value = 0;
    }
  }

  @override
  void dispose() {
    _interactionEndTimer?.cancel();
    _astronomyAnimationController.dispose();
    _astronomyTransitionController.dispose();
    _transformationController.removeListener(_handleTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    this.compact = false,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onReset,
  });

  final bool compact;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xDDF8F2DE),
        borderRadius: BorderRadius.circular(compact ? 999 : 14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity:
                compact ? VisualDensity.compact : VisualDensity.standard,
            iconSize: compact ? 20 : 24,
            padding: EdgeInsets.all(compact ? 8 : 12),
            tooltip: 'Zoom in',
            onPressed: onZoomIn,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            visualDensity:
                compact ? VisualDensity.compact : VisualDensity.standard,
            iconSize: compact ? 20 : 24,
            padding: EdgeInsets.all(compact ? 8 : 12),
            tooltip: 'Zoom out',
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove),
          ),
          IconButton(
            visualDensity:
                compact ? VisualDensity.compact : VisualDensity.standard,
            iconSize: compact ? 20 : 24,
            padding: EdgeInsets.all(compact ? 8 : 12),
            tooltip: 'Rotate left',
            onPressed: onRotateLeft,
            icon: const Icon(Icons.rotate_left),
          ),
          IconButton(
            visualDensity:
                compact ? VisualDensity.compact : VisualDensity.standard,
            iconSize: compact ? 20 : 24,
            padding: EdgeInsets.all(compact ? 8 : 12),
            tooltip: 'Rotate right',
            onPressed: onRotateRight,
            icon: const Icon(Icons.rotate_right),
          ),
          IconButton(
            visualDensity:
                compact ? VisualDensity.compact : VisualDensity.standard,
            iconSize: compact ? 20 : 24,
            padding: EdgeInsets.all(compact ? 8 : 12),
            tooltip: 'Reset view',
            onPressed: onReset,
            icon: const Icon(Icons.center_focus_strong),
          ),
        ],
      ),
    );
  }
}

class _MapTileLayer extends StatelessWidget {
  const _MapTileLayer({
    required this.baseUrl,
    required this.edgeMode,
    required this.tileVersion,
    required this.viewportSize,
    required this.tileZoom,
    required this.tileRange,
    required this.showParentFallback,
  });

  final String baseUrl;
  final EdgeRenderMode edgeMode;
  final String tileVersion;
  final Size viewportSize;
  final int tileZoom;
  final _TileRange tileRange;
  final bool showParentFallback;

  @override
  Widget build(BuildContext context) {
    final tileCount = 1 << tileZoom;
    final tileWidth = viewportSize.width / tileCount;
    final tileHeight = viewportSize.height / tileCount;
    final edgeSlug = _edgeModeSlug(edgeMode);
    final centerTileX = (tileRange.minX + tileRange.maxX) / 2;
    final centerTileY = (tileRange.minY + tileRange.maxY) / 2;
    final diskCenter = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final diskRadius = math.min(viewportSize.width, viewportSize.height) *
        (_mapRadiusScaleForSize(viewportSize) / 2);
    final visibleTiles = <_TileVisualRequest>[
      for (var tileX = tileRange.minX; tileX <= tileRange.maxX; tileX += 1)
        for (var tileY = tileRange.minY; tileY <= tileRange.maxY; tileY += 1)
          if (_rectIntersectsDisk(
            Rect.fromLTWH(
              tileX * tileWidth,
              tileY * tileHeight,
              tileWidth,
              tileHeight,
            ),
            diskCenter,
            diskRadius,
          ))
            _TileVisualRequest(
              x: tileX,
              y: tileY,
              priority: math.sqrt(
                math.pow(tileX - centerTileX, 2) +
                    math.pow(tileY - centerTileY, 2),
              ),
            ),
    ]..sort((left, right) => left.priority.compareTo(right.priority));
    final useParentFallback = showParentFallback && visibleTiles.length <= 12;

    return Stack(
      fit: StackFit.expand,
      children: [
        for (final tile in visibleTiles)
          Positioned(
            key: ValueKey('tile-$edgeSlug-$tileZoom-${tile.x}-${tile.y}'),
            left: tile.x * tileWidth,
            top: tile.y * tileHeight,
            width: tileWidth,
            height: tileHeight,
            child: _TileImage(
              baseUrl: baseUrl,
              edgeSlug: edgeSlug,
              tileVersion: tileVersion,
              tileZoom: tileZoom,
              tileX: tile.x,
              tileY: tile.y,
              tileWidth: tileWidth,
              tileHeight: tileHeight,
              showParentFallback: useParentFallback,
            ),
          ),
      ],
    );
  }
}

class _MapDiskClipper extends CustomClipper<Path> {
  const _MapDiskClipper();

  @override
  Path getClip(Size size) {
    final radius =
        math.min(size.width, size.height) * (_mapRadiusScaleForSize(size) / 2);
    final center = Offset(size.width / 2, size.height / 2);
    return Path()
      ..addOval(
        Rect.fromCircle(
          center: center,
          radius: radius,
        ),
      );
  }

  @override
  bool shouldReclip(covariant _MapDiskClipper oldClipper) => false;
}

class _TileImage extends StatelessWidget {
  const _TileImage({
    required this.baseUrl,
    required this.edgeSlug,
    required this.tileVersion,
    required this.tileZoom,
    required this.tileX,
    required this.tileY,
    required this.tileWidth,
    required this.tileHeight,
    required this.showParentFallback,
  });

  final String baseUrl;
  final String edgeSlug;
  final String tileVersion;
  final int tileZoom;
  final int tileX;
  final int tileY;
  final double tileWidth;
  final double tileHeight;
  final bool showParentFallback;

  @override
  Widget build(BuildContext context) {
    final tileUrl =
        '$baseUrl/map/tiles/$edgeSlug/$tileZoom/$tileX/$tileY.png?v=$tileVersion';
    return Stack(
      fit: StackFit.expand,
      children: [
        if (showParentFallback && tileZoom > 0)
          _ParentTileFallback(
            baseUrl: baseUrl,
            edgeSlug: edgeSlug,
            tileVersion: tileVersion,
            tileZoom: tileZoom,
            tileX: tileX,
            tileY: tileY,
            tileWidth: tileWidth,
            tileHeight: tileHeight,
          ),
        Image.network(
          tileUrl,
          fit: BoxFit.fill,
          gaplessPlayback: true,
          filterQuality: FilterQuality.none,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) {
              return child;
            }
            return const SizedBox.expand();
          },
          errorBuilder: (context, error, stackTrace) {
            return const SizedBox.expand();
          },
        ),
      ],
    );
  }
}

class _ParentTileFallback extends StatelessWidget {
  const _ParentTileFallback({
    required this.baseUrl,
    required this.edgeSlug,
    required this.tileVersion,
    required this.tileZoom,
    required this.tileX,
    required this.tileY,
    required this.tileWidth,
    required this.tileHeight,
  });

  final String baseUrl;
  final String edgeSlug;
  final String tileVersion;
  final int tileZoom;
  final int tileX;
  final int tileY;
  final double tileWidth;
  final double tileHeight;

  @override
  Widget build(BuildContext context) {
    final parentZoom = tileZoom - 1;
    final parentX = tileX ~/ 2;
    final parentY = tileY ~/ 2;
    final offsetX = (tileX % 2) * tileWidth;
    final offsetY = (tileY % 2) * tileHeight;
    final parentUrl =
        '$baseUrl/map/tiles/$edgeSlug/$parentZoom/$parentX/$parentY.png?v=$tileVersion';

    return ClipRect(
      child: Transform.translate(
        offset: Offset(-offsetX, -offsetY),
        child: SizedBox(
          width: tileWidth * 2,
          height: tileHeight * 2,
          child: Image.network(
            parentUrl,
            fit: BoxFit.fill,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (context, error, stackTrace) {
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
  }
}

class _BaseMapPainter extends CustomPainter {
  const _BaseMapPainter({
    required this.projectedScene,
    required this.edgeRenderMode,
  });

  final _ProjectedSceneCache projectedScene;
  final EdgeRenderMode edgeRenderMode;

  @override
  void paint(Canvas canvas, Size size) {
    final center = projectedScene.center;
    final radius = projectedScene.radius;
    final useFastCoastRendering = projectedScene.landEntries.length > 250;

    final outerDisk = Paint()..color = const Color(0xFF96C5C2);
    canvas.drawCircle(center, radius, outerDisk);

    final antarcticaPaint = Paint()..color = const Color(0xFF96C5C2);
    canvas.drawCircle(center, radius, antarcticaPaint);

    final oceanPaint = Paint()..color = const Color(0xFF96C5C2);
    canvas.drawCircle(center, radius * 0.85, oceanPaint);

    final glowPaint = Paint()
      ..color = const Color(0x22FDF5D7)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);
    canvas.drawCircle(center, radius * 0.78, glowPaint);

    final diskBorder = Paint()
      ..color = const Color(0xFFDCEFF4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius - 2, diskBorder);

    for (final entry in projectedScene.landEntries) {
      if (!entry.hasClosedRing) {
        continue;
      }

      if (!useFastCoastRendering) {
        canvas.drawShadow(entry.path, const Color(0x55000000), 10, false);
      }

      final fillPaint = Paint()
        ..color = entry.shape.fillColor.withAlpha(
          useFastCoastRendering ? 96 : 110,
        )
        ..style = PaintingStyle.fill;
      canvas.drawPath(entry.path, fillPaint);

      if (!useFastCoastRendering) {
        final highlightPaint = Paint()
          ..color = const Color(0x10FFFFFF)
          ..style = PaintingStyle.fill;
        canvas.drawPath(entry.path.shift(const Offset(-2, -2)), highlightPaint);
      }
    }

    final shouldDrawBoundaries = edgeRenderMode == EdgeRenderMode.country ||
        edgeRenderMode == EdgeRenderMode.both ||
        edgeRenderMode == EdgeRenderMode.coastline;
    if (shouldDrawBoundaries) {
      final clipBoundariesToLand = edgeRenderMode == EdgeRenderMode.coastline;
      if (clipBoundariesToLand) {
        canvas.save();
        canvas.clipPath(projectedScene.landClipPath);
      }
      for (final entry in projectedScene.boundaryEntries) {
        final strokePaint = Paint()
          ..color = entry.shape.strokeColor.withAlpha(
            useFastCoastRendering ? 110 : 132,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = useFastCoastRendering ? 0.75 : 0.95
          ..strokeCap = StrokeCap.butt
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(entry.path, strokePaint);
      }
      if (clipBoundariesToLand) {
        canvas.restore();
      }
    }

    if (edgeRenderMode == EdgeRenderMode.coastline ||
        edgeRenderMode == EdgeRenderMode.both) {
      for (final entry in projectedScene.landEntries) {
        _paintCoastStroke(
            canvas, entry.path, entry.shape, useFastCoastRendering);
      }
    }

    final centerDot = Paint()..color = const Color(0xFFF8F4E7);
    canvas.drawCircle(center, 6, centerDot);
  }

  void _paintCoastStroke(
    Canvas canvas,
    Path path,
    MapShape shape,
    bool useFastCoastRendering,
  ) {
    final strokePaint = Paint()
      ..color = shape.strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = shape.name == 'Antarctica Rim'
          ? (useFastCoastRendering ? 2.6 : 3.4)
          : (useFastCoastRendering ? 0.55 : 0.75)
      ..strokeCap =
          shape.name == 'Antarctica Rim' ? StrokeCap.round : StrokeCap.butt
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _BaseMapPainter oldDelegate) {
    return oldDelegate.projectedScene != projectedScene ||
        oldDelegate.edgeRenderMode != edgeRenderMode;
  }
}

class _FlatWorldPainter extends CustomPainter {
  _FlatWorldPainter({
    super.repaint,
    required this.projectedScene,
    required this.visibleSceneRect,
    required this.selectedShape,
    required this.selectedAstronomy,
    required this.markerAnchorPoints,
    required this.labelAnchorPoints,
    required this.markers,
    required this.labels,
    required this.showGrid,
    required this.showTimeZones,
    required this.useRealTimeZones,
    required this.gridStepDegrees,
    required this.edgeRenderMode,
    required this.showLabels,
    required this.showShapeLabels,
    required this.showStateBoundaries,
    required this.previousAstronomySnapshot,
    required this.astronomySnapshot,
    required this.skyCatalog,
    required this.astronomyTransitionAnimation,
    required this.showSunPath,
    required this.showMoonPath,
    required this.showStars,
    required this.showConstellations,
    required this.showConstellationsFullSky,
    required this.windSnapshot,
    required this.showWindAnimation,
    required this.showWindOverlay,
    required this.weatherAnimationLabel,
    required this.weatherOverlaySnapshot,
    required this.showWeatherOverlay,
    required this.animateWind,
    required this.visiblePlanetNames,
    required this.astronomyObserverName,
    required this.routePoints,
    required this.labelScale,
    required this.viewScale,
    required this.viewRotationRadians,
    required this.astronomyPulseAnimation,
    required this.isInteracting,
  });

  final _ProjectedSceneCache projectedScene;
  final Rect visibleSceneRect;
  final _SelectedShapeTarget? selectedShape;
  final _SelectedAstronomyTarget? selectedAstronomy;
  final List<Offset> markerAnchorPoints;
  final List<Offset> labelAnchorPoints;
  final List<PlaceMarker> markers;
  final List<MapLabel> labels;
  final bool showGrid;
  final bool showTimeZones;
  final bool useRealTimeZones;
  final int gridStepDegrees;
  final EdgeRenderMode edgeRenderMode;
  final bool showLabels;
  final bool showShapeLabels;
  final bool showStateBoundaries;
  final AstronomySnapshot? previousAstronomySnapshot;
  final AstronomySnapshot? astronomySnapshot;
  final SkyCatalog? skyCatalog;
  final Animation<double> astronomyTransitionAnimation;
  final bool showSunPath;
  final bool showMoonPath;
  final bool showStars;
  final bool showConstellations;
  final bool showConstellationsFullSky;
  final WindSnapshot? windSnapshot;
  final bool showWindAnimation;
  final bool showWindOverlay;
  final String weatherAnimationLabel;
  final WeatherOverlaySnapshot? weatherOverlaySnapshot;
  final bool showWeatherOverlay;
  final bool animateWind;
  final List<String> visiblePlanetNames;
  final String? astronomyObserverName;
  final List<PlaceMarker?> routePoints;
  final double labelScale;
  final double viewScale;
  final double viewRotationRadians;
  final Animation<double> astronomyPulseAnimation;
  final bool isInteracting;

  @override
  void paint(Canvas canvas, Size size) {
    final center = projectedScene.center;
    final mapRadius = projectedScene.mapRadius;
    final showOverlayLegend =
        showWeatherOverlay && weatherOverlaySnapshot != null;
    final showWindLegend =
        (showWindAnimation || showWindOverlay) && windSnapshot != null;

    if (showWeatherOverlay && weatherOverlaySnapshot != null) {
      _paintWeatherOverlayField(canvas, center, mapRadius);
    }

    if (showWindOverlay && windSnapshot != null) {
      _paintWindFieldOverlay(canvas, center, mapRadius);
    }

    if (showWindAnimation && windSnapshot != null) {
      _paintWindOverlay(canvas, center, mapRadius);
    }

    if (astronomySnapshot != null &&
        (showSunPath ||
            showMoonPath ||
            showStars ||
            showConstellations ||
            visiblePlanetNames.isNotEmpty)) {
      _paintAstronomyOverlay(canvas, center, mapRadius);
    }

    if (showGrid) {
      _paintGraticule(
        canvas,
        center,
        mapRadius,
        gridStepDegrees,
        viewScale,
      );
    }

    if (showTimeZones) {
      if (useRealTimeZones && projectedScene.timeZoneEntries.isNotEmpty) {
        _paintRealTimeZones(canvas);
      } else {
        _paintTimeZones(canvas, center, mapRadius);
      }
    }

    if (showShapeLabels && !isInteracting) {
      _paintShapeLabels(canvas);
    }

    if (showStateBoundaries) {
      _paintStateBoundaries(canvas);
    }

    _paintSelectedShapeHighlight(canvas);

    if (showLabels) {
      _paintLayerLabels(
        canvas,
        center,
        mapRadius,
        projectedScene.landClipPath,
        projectedScene.projectedLandRings,
      );
    }

    _paintSelectedAstronomyCallout(canvas, center, mapRadius);
    _paintSelectedShapeCallout(canvas);

    _paintMeasurementOverlay(canvas, center, mapRadius);

    final markerPaint = Paint()..color = const Color(0xFFE45C3A);
    for (var markerIndex = 0; markerIndex < markers.length; markerIndex += 1) {
      final marker = markers[markerIndex];
      final point = markerIndex < markerAnchorPoints.length
          ? markerAnchorPoints[markerIndex]
          : _project(center, mapRadius, marker.x, marker.y);
      final markerRadius = _screenStableRadius(
        marker.zone == 'antarctic_ring' ? 3.8 : 3.0,
        viewScale,
        minRadius: 1.1,
      );
      canvas.drawCircle(point, markerRadius, markerPaint);

      if (showLabels && !isInteracting) {
        final markerLabelFontSize = _markerLabelFontSize(viewScale);
        final textPainter = TextPainter(
          text: TextSpan(
            text: marker.name,
            style: TextStyle(
              color: Color(0xFF112A46),
              fontSize: markerLabelFontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 130);
        _paintAnchoredPointLabel(
          canvas: canvas,
          anchorPoint: point,
          labelPainter: textPainter,
          labelOffsetInScreen: const Offset(14, -14),
          dotRadius: markerRadius,
          dotPaint: markerPaint,
          leaderColor: const Color(0xAA112A46),
        );
      }
    }

    if (showOverlayLegend && showWindLegend) {
      _paintCombinedWeatherLegend(canvas);
    } else if (showOverlayLegend) {
      _paintWeatherOverlayLegend(canvas);
    } else if (showWindLegend) {
      _paintWindLegend(canvas, alignRight: showOverlayLegend);
    }

    if (projectedScene.landEntries.isEmpty &&
        projectedScene.boundaryEntries.isEmpty) {
      final emptyPainter = TextPainter(
        text: const TextSpan(
          text: 'No backend map layer loaded',
          style: TextStyle(
            color: Color(0xCCF8F4E7),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 40);

      emptyPainter.paint(
        canvas,
        Offset(
          center.dx - (emptyPainter.width / 2),
          center.dy - 24,
        ),
      );
    }
  }

  Offset _project(Offset center, double radius, double x, double y) {
    return Offset(
      center.dx + x * radius,
      center.dy + y * radius,
    );
  }

  Offset _resolveDisplayPoint({
    required Offset originalPoint,
    required Path landClipPath,
    required List<List<Offset>> projectedLandRings,
    double maxSnapDistanceInScreen = 20,
  }) {
    return _resolveDisplayPointForEdgeMode(
      originalPoint: originalPoint,
      landClipPath: landClipPath,
      projectedLandRings: projectedLandRings,
      edgeRenderMode: edgeRenderMode,
      viewScale: viewScale,
      maxSnapDistanceInScreen: maxSnapDistanceInScreen,
    );
  }

  void _paintGraticule(
    Canvas canvas,
    Offset center,
    double mapRadius,
    int stepDegrees,
    double viewScale,
  ) {
    final minorGridPaint = Paint()
      ..color = const Color(0x66FFF8DB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stepDegrees <= 10 ? 0.9 : 1.05;
    final majorGridPaint = Paint()
      ..color = const Color(0x88D6EEF2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stepDegrees <= 10 ? 1.15 : 1.3;
    final antarcticaBoundaryPaint = Paint()
      ..color = const Color(0xB8E1F1F3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stepDegrees <= 10 ? 1.35 : 1.5;

    final latitudeFontSize = _gridLatitudeLabelFontSize(stepDegrees, viewScale);
    final longitudeFontSize =
        _gridLongitudeLabelFontSize(stepDegrees, viewScale);
    final latitudeRings = _buildLatitudeGridValues(stepDegrees);
    for (final latitude in latitudeRings) {
      final ringRadius = mapRadius * _latitudeToRadiusRatio(latitude);
      final isMajor = _isMajorLatitude(latitude, stepDegrees);
      final ringPaint = latitude.round() == _innerWorldMinLatitude
          ? antarcticaBoundaryPaint
          : (isMajor ? majorGridPaint : minorGridPaint);
      canvas.drawCircle(center, ringRadius, ringPaint);

      if (latitude.round() == -90) {
        continue;
      }

      final latitudeLabelPainter = TextPainter(
        text: TextSpan(
          text: _formatLatitudeLabel(latitude),
          style: TextStyle(
            color: const Color(0xFF10283A),
            fontSize: latitudeFontSize,
            fontWeight: isMajor ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: 0.15,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelCenter = Offset(
        center.dx,
        center.dy + ringRadius + 6 - (latitudeLabelPainter.height / 2),
      );

      _paintUprightLabel(
        canvas: canvas,
        center: labelCenter,
        labelPainter: latitudeLabelPainter,
      );
    }

    final longitudes = _buildLongitudeGridValues(stepDegrees);
    for (final longitude in longitudes) {
      final theta = _longitudeToThetaRadians(longitude.toDouble());
      final spokeEnd = Offset(
        center.dx + math.cos(theta) * mapRadius,
        center.dy + math.sin(theta) * mapRadius,
      );
      final isMajor = _isMajorLongitude(longitude, stepDegrees);
      final spokePaint = isMajor ? majorGridPaint : minorGridPaint;
      canvas.drawLine(center, spokeEnd, spokePaint);

      final labelCenter = Offset(
        center.dx + math.cos(theta) * (mapRadius + 18),
        center.dy + math.sin(theta) * (mapRadius + 18),
      );
      final labelText = _isSharedSouthWestLabel(-90, longitude)
          ? '90SW'
          : _formatLongitudeLabel(longitude);
      final longitudeLabelPainter = TextPainter(
        text: TextSpan(
          text: labelText,
          style: TextStyle(
            color: const Color(0xFF10283A),
            fontSize: longitudeFontSize,
            fontWeight: isMajor ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      _paintUprightLabel(
        canvas: canvas,
        center: labelCenter,
        labelPainter: longitudeLabelPainter,
      );
    }
  }

  void _paintShapeLabels(Canvas canvas) {
    for (final entry in projectedScene.landEntries) {
      if (!entry.hasClosedRing || entry.shape.name == 'Antarctica Rim') {
        continue;
      }

      final shapeLabelFontSize = _shapeLabelFontSize(viewScale);
      final labelPainter = TextPainter(
        text: TextSpan(
          text: entry.shape.name,
          style: TextStyle(
            color: const Color(0xFF10283A),
            fontSize: shapeLabelFontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 120);

      _paintUprightLabel(
        canvas: canvas,
        center: entry.bounds.center,
        labelPainter: labelPainter,
      );
    }
  }

  void _paintTimeZones(
    Canvas canvas,
    Offset center,
    double mapRadius,
  ) {
    final worldClipPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: mapRadius));
    final timeZoneOffsets = _buildTimeZoneOffsets();

    canvas.save();
    canvas.clipPath(worldClipPath);
    for (var index = 0; index < timeZoneOffsets.length; index += 1) {
      final offsetHours = timeZoneOffsets[index];
      final centerLongitude = offsetHours * 15.0;
      final startLongitude = centerLongitude - 7.5;
      final endLongitude = centerLongitude + 7.5;
      final wedgePath = Path()..moveTo(center.dx, center.dy);
      final startPoint = _projectLatLon(center, mapRadius, -90, startLongitude);
      wedgePath.lineTo(startPoint.dx, startPoint.dy);
      for (var step = 1; step <= 12; step += 1) {
        final t = step / 12;
        final longitude =
            startLongitude + ((endLongitude - startLongitude) * t);
        final edgePoint = _projectLatLon(center, mapRadius, -90, longitude);
        wedgePath.lineTo(edgePoint.dx, edgePoint.dy);
      }
      wedgePath.close();

      final fillPaint = Paint()
        ..color =
            index.isEven ? const Color(0x122E557A) : const Color(0x060F2940)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.drawPath(wedgePath, fillPaint);
    }
    canvas.restore();

    final spokePaint = Paint()
      ..color = const Color(0x55557886)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _screenStableRadius(0.9, viewScale, minRadius: 0.45)
      ..isAntiAlias = true;

    for (final offsetHours in timeZoneOffsets) {
      final boundaryLongitude = (offsetHours * 15.0) - 7.5;
      final edgePoint =
          _projectLatLon(center, mapRadius, -90, boundaryLongitude);
      canvas.drawLine(center, edgePoint, spokePaint);
    }

    if (isInteracting && viewScale > 2.4) {
      return;
    }

    final labelLatitude = viewScale >= 2.2 ? -76.0 : -82.0;
    final labelFontSize = _timeZoneLabelFontSize(viewScale);
    for (final offsetHours in timeZoneOffsets) {
      final labelPoint = _projectLatLon(
        center,
        mapRadius,
        labelLatitude,
        offsetHours * 15.0,
      );
      final labelPainter = TextPainter(
        text: TextSpan(
          text: _formatUtcOffsetLabel(offsetHours),
          style: TextStyle(
            color: const Color(0xFF10283A),
            fontSize: labelFontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 84);

      _paintUprightLabel(
        canvas: canvas,
        center: labelPoint,
        labelPainter: labelPainter,
      );
    }
  }

  void _paintRealTimeZones(Canvas canvas) {
    if (projectedScene.timeZoneEntries.isEmpty) {
      return;
    }

    final useLightRender = projectedScene.timeZoneEntries.length > 800;
    canvas.save();
    canvas.clipPath(projectedScene.landClipPath);
    for (var index = 0;
        index < projectedScene.timeZoneEntries.length;
        index += 1) {
      final entry = projectedScene.timeZoneEntries[index];
      if (!entry.hasClosedRing) {
        continue;
      }

      final fillPaint = Paint()
        ..color = entry.shape.fillColor.withAlpha(useLightRender ? 78 : 104)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.drawPath(entry.path, fillPaint);
    }

    for (final entry in projectedScene.timeZoneEntries) {
      final strokePaint = Paint()
        ..color = entry.shape.strokeColor.withAlpha(useLightRender ? 188 : 228)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _screenStableRadius(
          useLightRender ? 1.2 : 1.55,
          viewScale,
          minRadius: 0.65,
        )
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawPath(entry.path, strokePaint);
    }

    if (!isInteracting) {
      for (final entry in projectedScene.timeZoneEntries) {
        final timeZoneLabel = entry.shape.timeZoneLabel;
        if (timeZoneLabel == null || timeZoneLabel.isEmpty) {
          continue;
        }
        if (entry.bounds.width * viewScale < 54 ||
            entry.bounds.height * viewScale < 20) {
          continue;
        }

        final labelPainter = TextPainter(
          text: TextSpan(
            text: timeZoneLabel,
            style: TextStyle(
              color: const Color(0xFF10283A),
              fontSize: _timeZoneLabelFontSize(viewScale),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 86);

        _paintUprightLabel(
          canvas: canvas,
          center: entry.bounds.center,
          labelPainter: labelPainter,
        );
      }
    }
    canvas.restore();
  }

  void _paintStateBoundaries(Canvas canvas) {
    if (projectedScene.stateBoundaryEntries.isEmpty) {
      return;
    }

    canvas.save();
    canvas.clipPath(projectedScene.landClipPath);
    for (final entry in projectedScene.stateBoundaryEntries) {
      if (!entry.bounds.overlaps(visibleSceneRect.inflate(24))) {
        continue;
      }
      final strokePaint = Paint()
        ..color = entry.shape.strokeColor.withAlpha(isInteracting ? 96 : 124)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _screenStableRadius(
          isInteracting ? 0.75 : 0.95,
          viewScale,
          minRadius: 0.28,
        )
        ..strokeCap = StrokeCap.butt
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      canvas.drawPath(entry.path, strokePaint);
    }
    canvas.restore();
  }

  void _paintSelectedShapeHighlight(Canvas canvas) {
    final matchingEntries = _selectedShapeEntries();
    if (matchingEntries.isEmpty) {
      return;
    }

    final selection = selectedShape!;
    canvas.save();
    canvas.clipPath(projectedScene.landClipPath);
    final fillPaint = Paint()
      ..color = selection.role == 'state_boundary'
          ? const Color(0x33458FB0)
          : const Color(0x225B8C74)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = selection.role == 'state_boundary'
          ? const Color(0xFF2C6D8E)
          : const Color(0xFF2C6A59)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _screenStableRadius(2.1, viewScale, minRadius: 0.9)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    for (final entry in matchingEntries) {
      canvas.drawPath(entry.path, fillPaint);
      canvas.drawPath(entry.path, strokePaint);
    }
    canvas.restore();
  }

  void _paintSelectedShapeCallout(Canvas canvas) {
    final matchingEntries = _selectedShapeEntries();
    if (matchingEntries.isEmpty) {
      return;
    }

    Rect combinedBounds = matchingEntries.first.bounds;
    for (final entry in matchingEntries.skip(1)) {
      combinedBounds = combinedBounds.expandToInclude(entry.bounds);
    }

    final anchor = Offset(
      combinedBounds.center.dx.clamp(
        visibleSceneRect.left + 40,
        visibleSceneRect.right - 40,
      ),
      (combinedBounds.top - (18 / viewScale.clamp(1.0, 24.0))).clamp(
        visibleSceneRect.top + 20,
        visibleSceneRect.bottom - 20,
      ),
    );
    final selection = selectedShape!;
    final labelPainter = TextPainter(
      text: TextSpan(
        text: selection.displayName,
        style: TextStyle(
          color: const Color(0xFF0F1720),
          fontSize: _layerLabelFontSize('state', viewScale),
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 180);
    final backgroundRect = Rect.fromCenter(
      center: anchor,
      width: labelPainter.width + 18,
      height: labelPainter.height + 10,
    );
    final background = RRect.fromRectAndRadius(
      backgroundRect,
      const Radius.circular(999),
    );
    final backgroundPaint = Paint()
      ..color = selection.role == 'state_boundary'
          ? const Color(0xE62C6D8E)
          : const Color(0xE62C6A59);
    _paintUprightLabel(
      canvas: canvas,
      center: anchor,
      labelPainter: labelPainter,
      background: background,
      backgroundPaint: backgroundPaint,
    );
  }

  List<_ProjectedShapeEntry> _selectedShapeEntries() {
    final selection = selectedShape;
    if (selection == null) {
      return const <_ProjectedShapeEntry>[];
    }

    final entries = switch (selection.role) {
      'state_boundary' => projectedScene.stateBoundaryEntries,
      'boundary' => projectedScene.boundaryEntries,
      _ => const <_ProjectedShapeEntry>[],
    };
    if (entries.isEmpty) {
      return const <_ProjectedShapeEntry>[];
    }

    return entries
        .where(
          (entry) =>
              _selectionDisplayName(entry.shape.name) == selection.name &&
              entry.hasClosedRing &&
              entry.bounds.overlaps(visibleSceneRect.inflate(32)),
        )
        .toList(growable: false);
  }

  Offset _projectLatLon(
    Offset center,
    double mapRadius,
    double latitude,
    double longitude,
  ) {
    final radiusRatio = _latitudeToRadiusRatio(latitude);
    final theta = _longitudeToThetaRadians(longitude);
    return Offset(
      center.dx + math.cos(theta) * mapRadius * radiusRatio,
      center.dy + math.sin(theta) * mapRadius * radiusRatio,
    );
  }

  double _hemisphereIncidence(
    double latitude,
    double longitude,
    double sourceLatitude,
    double sourceLongitude,
  ) {
    final latitudeRadians = latitude * math.pi / 180;
    final sourceLatitudeRadians = sourceLatitude * math.pi / 180;
    final deltaLongitude = (longitude - sourceLongitude) * math.pi / 180;
    return math.sin(latitudeRadians) * math.sin(sourceLatitudeRadians) +
        math.cos(latitudeRadians) *
            math.cos(sourceLatitudeRadians) *
            math.cos(deltaLongitude);
  }

  AstronomySnapshot? _resolvedAstronomySnapshot() {
    final current = astronomySnapshot;
    final previous = previousAstronomySnapshot;
    final t = astronomyTransitionAnimation.value.clamp(0.0, 1.0);
    if (current == null || previous == null || t >= 1) {
      return current;
    }
    return AstronomySnapshot(
      timestampUtc: current.timestampUtc,
      source: current.source,
      greenwichSiderealDegrees: _lerpCircularDegrees(
        previous.greenwichSiderealDegrees,
        current.greenwichSiderealDegrees,
        t,
      ),
      sun: _lerpAstronomyBody(previous.sun, current.sun, t),
      moon: _lerpAstronomyBody(previous.moon, current.moon, t),
      planets: _lerpAstronomyBodies(previous.planets, current.planets, t),
      observer: current.observer,
    );
  }

  AstronomyBody _lerpAstronomyBody(
    AstronomyBody start,
    AstronomyBody end,
    double t,
  ) {
    final startIllumination = start.illuminationFraction;
    final endIllumination = end.illuminationFraction;
    return AstronomyBody(
      name: end.name,
      subpoint: _lerpPlaceMarker(start.subpoint, end.subpoint, t),
      path: end.path,
      phaseName: end.phaseName,
      illuminationFraction: startIllumination == null || endIllumination == null
          ? endIllumination
          : ui.lerpDouble(startIllumination, endIllumination, t),
    );
  }

  List<AstronomyBody> _lerpAstronomyBodies(
    List<AstronomyBody> previousBodies,
    List<AstronomyBody> currentBodies,
    double t,
  ) {
    final previousByName = <String, AstronomyBody>{
      for (final body in previousBodies) body.name: body,
    };
    return currentBodies.map((body) {
      final previousBody = previousByName[body.name];
      if (previousBody == null) {
        return body;
      }
      return _lerpAstronomyBody(previousBody, body, t);
    }).toList(growable: false);
  }

  PlaceMarker _lerpPlaceMarker(PlaceMarker start, PlaceMarker end, double t) {
    return PlaceMarker(
      name: end.name,
      latitude: ui.lerpDouble(start.latitude, end.latitude, t) ?? end.latitude,
      longitude: _lerpLongitude(start.longitude, end.longitude, t),
      x: ui.lerpDouble(start.x, end.x, t) ?? end.x,
      y: ui.lerpDouble(start.y, end.y, t) ?? end.y,
      zone: end.zone,
    );
  }

  double _lerpLongitude(double start, double end, double t) {
    var delta = end - start;
    if (delta > 180) {
      delta -= 360;
    } else if (delta < -180) {
      delta += 360;
    }
    final lerped = start + delta * t;
    if (lerped > 180) {
      return lerped - 360;
    }
    if (lerped < -180) {
      return lerped + 360;
    }
    return lerped;
  }

  double _lerpCircularDegrees(double start, double end, double t) {
    var delta = end - start;
    if (delta > 180) {
      delta -= 360;
    } else if (delta < -180) {
      delta += 360;
    }
    final lerped = start + delta * t;
    if (lerped < 0) {
      return lerped + 360;
    }
    if (lerped >= 360) {
      return lerped - 360;
    }
    return lerped;
  }

  Color _windSpeedColor(
    double speedMps,
    double minSpeedMps,
    double maxSpeedMps,
  ) {
    final span = math.max(0.1, maxSpeedMps - minSpeedMps);
    final t = ((speedMps - minSpeedMps) / span).clamp(0.0, 1.0).toDouble();
    return _overlayScaleColor(t);
  }

  Color _overlayScaleColor(double t) {
    const stopValues = <double>[0.0, 0.16, 0.32, 0.5, 0.68, 0.84, 1.0];
    const stopColors = <Color>[
      Color(0xFF7F3FBF),
      Color(0xFF4B3FBF),
      Color(0xFF2C6EE8),
      Color(0xFF2FAE63),
      Color(0xFFF2D13D),
      Color(0xFFF28C28),
      Color(0xFFE63B2E),
    ];
    for (var index = 0; index < stopValues.length - 1; index += 1) {
      final currentValue = stopValues[index];
      final nextValue = stopValues[index + 1];
      if (t <= nextValue) {
        final localT = ((t - currentValue) / (nextValue - currentValue))
            .clamp(0.0, 1.0)
            .toDouble();
        return Color.lerp(stopColors[index], stopColors[index + 1], localT) ??
            stopColors[index + 1];
      }
    }
    return stopColors.last;
  }

  WeatherOverlayValue? _sampleWeatherOverlayField(
    WeatherOverlaySnapshot snapshot,
    double latitude,
    double longitude,
  ) {
    final neighborRadiusDegrees =
        math.max(12.0, snapshot.gridStepDegrees * 1.9).toDouble();
    final candidates = <({double distance, WeatherOverlayValue value})>[];

    for (final value in snapshot.values) {
      final latitudeDistance = (value.latitude - latitude).abs();
      if (latitudeDistance > neighborRadiusDegrees) {
        continue;
      }
      final longitudeDistance = _longitudeDistanceDegrees(
        value.longitude,
        longitude,
      );
      if (longitudeDistance > neighborRadiusDegrees * 1.25) {
        continue;
      }
      final distance = math.sqrt(
        (latitudeDistance * latitudeDistance) +
            (longitudeDistance * longitudeDistance),
      );
      if (distance <= 0.001) {
        return value;
      }
      candidates.add((distance: distance, value: value));
    }

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort((left, right) => left.distance.compareTo(right.distance));
    final nearest = candidates.take(6);
    var totalWeight = 0.0;
    var summedValue = 0.0;

    for (final candidate in nearest) {
      final weight = 1.0 / math.max(0.2, candidate.distance);
      totalWeight += weight;
      summedValue += candidate.value.value * weight;
    }

    if (totalWeight <= 0) {
      return null;
    }

    return WeatherOverlayValue(
      latitude: latitude,
      longitude: longitude,
      value: summedValue / totalWeight,
    );
  }

  ({double min, double max}) _windColorDomain(WindSnapshot snapshot) {
    if (snapshot.vectors.isEmpty) {
      return (min: 0.0, max: 1.0);
    }

    final speeds = snapshot.vectors
        .map((vector) => vector.speedMps)
        .toList(growable: false)
      ..sort();
    final lowIndex = ((speeds.length - 1) * 0.06).round();
    final highIndex = ((speeds.length - 1) * 0.82).round();
    final minSpeed = speeds[lowIndex.clamp(0, speeds.length - 1)];
    final maxSpeed = speeds[highIndex.clamp(0, speeds.length - 1)];
    if (maxSpeed <= minSpeed) {
      return (
        min: snapshot.minSpeedMps,
        max: math.max(snapshot.maxSpeedMps, snapshot.minSpeedMps + 0.1),
      );
    }
    return (min: minSpeed, max: maxSpeed);
  }

  void _paintWindArrowhead(
    Canvas canvas, {
    required Offset start,
    required Offset end,
    required Color color,
    required double speedT,
  }) {
    final direction = end - start;
    final distance = direction.distance;
    if (distance <= 0.001) {
      return;
    }
    final unit = direction / distance;
    final normal = Offset(-unit.dy, unit.dx);
    final headLength = (7.0 + (4.0 * speedT)) / viewScale.clamp(1.0, 24.0);
    final headWidth = (3.2 + (1.8 * speedT)) / viewScale.clamp(1.0, 24.0);
    final base = end - (unit * headLength);
    final arrowPath = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        base.dx + (normal.dx * headWidth),
        base.dy + (normal.dy * headWidth),
      )
      ..lineTo(
        base.dx - (normal.dx * headWidth),
        base.dy - (normal.dy * headWidth),
      )
      ..close();
    canvas.drawPath(
      arrowPath,
      Paint()..color = color,
    );
    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = const Color(0xEAF8FBF6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _screenStableRadius(0.7, viewScale, minRadius: 0.3),
    );
  }

  WindVector? _sampleWindField(
    WindSnapshot snapshot,
    double latitude,
    double longitude,
  ) {
    final neighborRadiusDegrees =
        math.max(12.0, snapshot.gridStepDegrees * 1.9).toDouble();
    final candidates = <({double distance, WindVector vector})>[];

    for (final vector in snapshot.vectors) {
      final latitudeDistance = (vector.latitude - latitude).abs();
      if (latitudeDistance > neighborRadiusDegrees) {
        continue;
      }
      final longitudeDistance = _longitudeDistanceDegrees(
        vector.longitude,
        longitude,
      );
      if (longitudeDistance > neighborRadiusDegrees * 1.25) {
        continue;
      }
      final distance = math.sqrt(
        (latitudeDistance * latitudeDistance) +
            (longitudeDistance * longitudeDistance),
      );
      if (distance <= 0.001) {
        return vector;
      }
      candidates.add((distance: distance, vector: vector));
    }

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort((left, right) => left.distance.compareTo(right.distance));
    final nearest = candidates.take(6);
    var totalWeight = 0.0;
    var summedU = 0.0;
    var summedV = 0.0;

    for (final candidate in nearest) {
      final weight = 1.0 / math.max(0.2, candidate.distance);
      totalWeight += weight;
      summedU += candidate.vector.uMps * weight;
      summedV += candidate.vector.vMps * weight;
    }

    if (totalWeight <= 0) {
      return null;
    }

    final uMps = summedU / totalWeight;
    final vMps = summedV / totalWeight;
    return WindVector(
      latitude: latitude,
      longitude: longitude,
      uMps: uMps,
      vMps: vMps,
      speedMps: math.sqrt((uMps * uMps) + (vMps * vMps)),
    );
  }

  List<_WindTracePoint> _traceWindDirection(
    WindSnapshot snapshot, {
    required double seedLatitude,
    required double seedLongitude,
    required int directionSign,
    required int maxSteps,
  }) {
    final points = <_WindTracePoint>[];
    var latitude = seedLatitude;
    var longitude = seedLongitude;

    for (var step = 0; step < maxSteps; step += 1) {
      final sample = _sampleWindField(snapshot, latitude, longitude);
      if (sample == null || sample.speedMps <= 0.18) {
        break;
      }

      points.add(
        _WindTracePoint(
          latitude: latitude,
          longitude: longitude,
          speedMps: sample.speedMps,
        ),
      );

      final longitudeScale = math.max(
        0.28,
        math.cos(latitude * math.pi / 180).abs(),
      );
      final directionLatitude = sample.vMps / math.max(sample.speedMps, 0.1);
      final directionLongitude =
          (sample.uMps / math.max(sample.speedMps, 0.1)) / longitudeScale;
      final directionMagnitude = math.sqrt(
        (directionLatitude * directionLatitude) +
            (directionLongitude * directionLongitude),
      );
      if (directionMagnitude <= 0.001) {
        break;
      }

      final normalizedLatitude = directionLatitude / directionMagnitude;
      final normalizedLongitude = directionLongitude / directionMagnitude;
      final stepDegrees =
          (snapshot.gridStepDegrees * 0.24).clamp(1.45, 3.6).toDouble();
      latitude = (latitude + (normalizedLatitude * stepDegrees * directionSign))
          .clamp(-88.0, 88.0);
      longitude = _normalizeSignedDegrees(
        longitude + (normalizedLongitude * stepDegrees * directionSign),
      );
    }

    return points;
  }

  List<_WindTracePoint> _buildWindStreamline(
    WindSnapshot snapshot, {
    required double seedLatitude,
    required double seedLongitude,
  }) {
    final backward = _traceWindDirection(
      snapshot,
      seedLatitude: seedLatitude,
      seedLongitude: seedLongitude,
      directionSign: -1,
      maxSteps: 12,
    );
    final forward = _traceWindDirection(
      snapshot,
      seedLatitude: seedLatitude,
      seedLongitude: seedLongitude,
      directionSign: 1,
      maxSteps: 16,
    );

    final streamline = <_WindTracePoint>[
      ...backward.reversed.skip(backward.isEmpty ? 0 : 1),
      ...forward,
    ];
    return streamline.length >= 4 ? streamline : const <_WindTracePoint>[];
  }

  Path _buildWindPath(
    List<_WindTracePoint> streamline,
    Offset center,
    double mapRadius,
  ) {
    final path = Path();
    if (streamline.isEmpty) {
      return path;
    }
    final projectedPoints = <Offset>[
      for (final tracePoint in streamline)
        _projectLatLon(
          center,
          mapRadius,
          tracePoint.latitude,
          tracePoint.longitude,
        ),
    ];
    final firstPoint = projectedPoints.first;
    path.moveTo(firstPoint.dx, firstPoint.dy);

    if (projectedPoints.length == 1) {
      return path;
    }
    if (projectedPoints.length == 2) {
      final secondPoint = projectedPoints[1];
      path.lineTo(secondPoint.dx, secondPoint.dy);
      return path;
    }

    for (var index = 1; index < projectedPoints.length - 1; index += 1) {
      final current = projectedPoints[index];
      final next = projectedPoints[index + 1];
      final midpoint = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
      path.quadraticBezierTo(current.dx, current.dy, midpoint.dx, midpoint.dy);
    }
    final penultimate = projectedPoints[projectedPoints.length - 2];
    final last = projectedPoints.last;
    path.quadraticBezierTo(penultimate.dx, penultimate.dy, last.dx, last.dy);
    return path;
  }

  void _paintWindFieldOverlay(
    Canvas canvas,
    Offset center,
    double mapRadius,
  ) {
    final snapshot = windSnapshot;
    if (snapshot == null || snapshot.vectors.isEmpty) {
      return;
    }

    final colorDomain = _windColorDomain(snapshot);
    final minSpeed = colorDomain.min;
    final maxSpeed = math.max(colorDomain.max, minSpeed + 0.1);
    final latitudeStep = isInteracting
        ? math.max(6.0, snapshot.gridStepDegrees.toDouble())
        : math.max(4.0, snapshot.gridStepDegrees / 2);
    final longitudeStep = latitudeStep;
    final positions = <Offset>[];
    final colors = <Color>[];
    final indices = <int>[];

    for (double latitude = 90.0; latitude > -90.0; latitude -= latitudeStep) {
      final nextLatitude = math.max(-90.0, latitude - latitudeStep);
      for (double longitude = -180.0;
          longitude < 180.0;
          longitude += longitudeStep) {
        final nextLongitude = math.min(180.0, longitude + longitudeStep);
        final topLeft = _projectLatLon(center, mapRadius, latitude, longitude);
        final topRight = _projectLatLon(
          center,
          mapRadius,
          latitude,
          nextLongitude,
        );
        final bottomRight = _projectLatLon(
          center,
          mapRadius,
          nextLatitude,
          nextLongitude,
        );
        final bottomLeft = _projectLatLon(
          center,
          mapRadius,
          nextLatitude,
          longitude,
        );

        final baseIndex = positions.length;
        positions.addAll([topLeft, topRight, bottomRight, bottomLeft]);
        colors.addAll([
          _windShadeColor(
            snapshot: snapshot,
            latitude: latitude,
            longitude: longitude,
            minSpeed: minSpeed,
            maxSpeed: maxSpeed,
          ),
          _windShadeColor(
            snapshot: snapshot,
            latitude: latitude,
            longitude: nextLongitude,
            minSpeed: minSpeed,
            maxSpeed: maxSpeed,
          ),
          _windShadeColor(
            snapshot: snapshot,
            latitude: nextLatitude,
            longitude: nextLongitude,
            minSpeed: minSpeed,
            maxSpeed: maxSpeed,
          ),
          _windShadeColor(
            snapshot: snapshot,
            latitude: nextLatitude,
            longitude: longitude,
            minSpeed: minSpeed,
            maxSpeed: maxSpeed,
          ),
        ]);
        indices.addAll([
          baseIndex,
          baseIndex + 1,
          baseIndex + 2,
          baseIndex,
          baseIndex + 2,
          baseIndex + 3,
        ]);
      }
    }

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: mapRadius)),
    );
    canvas.drawVertices(
      ui.Vertices(
        ui.VertexMode.triangles,
        positions,
        colors: colors,
        indices: indices,
      ),
      BlendMode.srcOver,
      Paint()..isAntiAlias = true,
    );
    canvas.restore();
  }

  void _paintWeatherOverlayField(
    Canvas canvas,
    Offset center,
    double mapRadius,
  ) {
    final snapshot = weatherOverlaySnapshot;
    if (snapshot == null || snapshot.values.isEmpty) {
      return;
    }

    final minValue = snapshot.minValue;
    final maxValue = math.max(snapshot.maxValue, minValue + 0.1);
    final latitudeStep = isInteracting
        ? math.max(6.0, snapshot.gridStepDegrees.toDouble())
        : math.max(4.0, snapshot.gridStepDegrees / 2);
    final longitudeStep = latitudeStep;
    final positions = <Offset>[];
    final colors = <Color>[];
    final indices = <int>[];

    for (double latitude = 90.0; latitude > -90.0; latitude -= latitudeStep) {
      final nextLatitude = math.max(-90.0, latitude - latitudeStep);
      for (double longitude = -180.0;
          longitude < 180.0;
          longitude += longitudeStep) {
        final nextLongitude = math.min(180.0, longitude + longitudeStep);
        final topLeft = _projectLatLon(center, mapRadius, latitude, longitude);
        final topRight = _projectLatLon(
          center,
          mapRadius,
          latitude,
          nextLongitude,
        );
        final bottomRight = _projectLatLon(
          center,
          mapRadius,
          nextLatitude,
          nextLongitude,
        );
        final bottomLeft = _projectLatLon(
          center,
          mapRadius,
          nextLatitude,
          longitude,
        );

        final baseIndex = positions.length;
        positions.addAll([topLeft, topRight, bottomRight, bottomLeft]);
        colors.addAll([
          _weatherOverlayShadeColor(
            snapshot: snapshot,
            latitude: latitude,
            longitude: longitude,
            minValue: minValue,
            maxValue: maxValue,
          ),
          _weatherOverlayShadeColor(
            snapshot: snapshot,
            latitude: latitude,
            longitude: nextLongitude,
            minValue: minValue,
            maxValue: maxValue,
          ),
          _weatherOverlayShadeColor(
            snapshot: snapshot,
            latitude: nextLatitude,
            longitude: nextLongitude,
            minValue: minValue,
            maxValue: maxValue,
          ),
          _weatherOverlayShadeColor(
            snapshot: snapshot,
            latitude: nextLatitude,
            longitude: longitude,
            minValue: minValue,
            maxValue: maxValue,
          ),
        ]);
        indices.addAll([
          baseIndex,
          baseIndex + 1,
          baseIndex + 2,
          baseIndex,
          baseIndex + 2,
          baseIndex + 3,
        ]);
      }
    }

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: mapRadius)),
    );
    canvas.drawVertices(
      ui.Vertices(
        ui.VertexMode.triangles,
        positions,
        colors: colors,
        indices: indices,
      ),
      BlendMode.srcOver,
      Paint()..isAntiAlias = true,
    );
    canvas.restore();
  }

  Color _weatherOverlayShadeColor({
    required WeatherOverlaySnapshot snapshot,
    required double latitude,
    required double longitude,
    required double minValue,
    required double maxValue,
  }) {
    final sample = _sampleWeatherOverlayField(snapshot, latitude, longitude);
    if (sample == null) {
      return const Color(0x00000000);
    }

    final valueT = ((sample.value - minValue) / (maxValue - minValue))
        .clamp(0.0, 1.0)
        .toDouble();
    final baseColor = _overlayScaleColor(valueT);
    return baseColor.withAlpha((38 + (126 * valueT)).round().clamp(0, 255));
  }

  Color _windShadeColor({
    required WindSnapshot snapshot,
    required double latitude,
    required double longitude,
    required double minSpeed,
    required double maxSpeed,
  }) {
    final sample = _sampleWindField(snapshot, latitude, longitude);
    if (sample == null) {
      return const Color(0x00000000);
    }

    final speedT =
        ((sample.speedMps - minSpeed) / (maxSpeed - minSpeed)).clamp(0.0, 1.0);
    final baseColor = _windSpeedColor(sample.speedMps, minSpeed, maxSpeed);
    return baseColor.withAlpha((38 + (126 * speedT)).round().clamp(0, 255));
  }

  void _paintWindOverlay(
    Canvas canvas,
    Offset center,
    double mapRadius,
  ) {
    final snapshot = windSnapshot;
    if (snapshot == null || snapshot.vectors.isEmpty) {
      return;
    }

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: mapRadius)),
    );

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final windPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final colorDomain = _windColorDomain(snapshot);
    final minSpeed = colorDomain.min;
    final maxSpeed = math.max(colorDomain.max, minSpeed + 0.1);
    final animationPhase = animateWind ? astronomyPulseAnimation.value : 0.5;

    final seedLatitudes = <double>{
      for (final vector in snapshot.vectors) vector.latitude,
    }.toList()
      ..sort();
    final seedLongitudes = <double>{
      for (final vector in snapshot.vectors) vector.longitude,
    }.toList()
      ..sort();
    final halfStep = (snapshot.gridStepDegrees / 2).toDouble();
    final seeds = <({double latitude, double longitude, double seed})>[
      for (final vector in snapshot.vectors)
        (
          latitude: vector.latitude,
          longitude: vector.longitude,
          seed: (((vector.latitude + 90) * 0.017) +
                  ((vector.longitude + 180) * 0.0097))
              .remainder(1.0),
        ),
    ];
    if (snapshot.gridStepDegrees >= 12) {
      for (var rowIndex = 0; rowIndex < seedLatitudes.length; rowIndex += 1) {
        final latitude = seedLatitudes[rowIndex];
        final longitudeOffset = rowIndex.isEven ? halfStep : 0.0;
        for (final longitude in seedLongitudes) {
          final shiftedLongitude =
              _normalizeSignedDegrees(longitude + longitudeOffset);
          seeds.add(
            (
              latitude: latitude.clamp(-82.0, 82.0),
              longitude: shiftedLongitude,
              seed: (((latitude + 90) * 0.013) +
                      ((shiftedLongitude + 180) * 0.011))
                  .remainder(1.0),
            ),
          );
        }
      }
    }

    for (final seed in seeds) {
      final streamline = _buildWindStreamline(
        snapshot,
        seedLatitude: seed.latitude,
        seedLongitude: seed.longitude,
      );
      if (streamline.isEmpty) {
        continue;
      }

      final averageSpeed = streamline
              .map((tracePoint) => tracePoint.speedMps)
              .fold<double>(0, (sum, speed) => sum + speed) /
          streamline.length;
      final peakSpeed = streamline
          .map((tracePoint) => tracePoint.speedMps)
          .fold<double>(0, math.max);
      final representativeSpeed = (averageSpeed * 0.5) + (peakSpeed * 0.5);
      final speedT = ((representativeSpeed - minSpeed) / (maxSpeed - minSpeed))
          .clamp(0.0, 1.0);
      final lineColor =
          _windSpeedColor(representativeSpeed, minSpeed, maxSpeed);
      final alpha = (56 + (118 * speedT)).round().clamp(0, 255);
      final fullPath = _buildWindPath(streamline, center, mapRadius);

      outlinePaint
        ..color = lineColor.withAlpha((alpha * 0.16).round())
        ..strokeWidth = _screenStableRadius(3.4, viewScale, minRadius: 1.1);
      windPaint
        ..color = lineColor.withAlpha((alpha * 0.55).round())
        ..strokeWidth = _screenStableRadius(1.55, viewScale, minRadius: 0.62);
      canvas.drawPath(fullPath, outlinePaint);
      canvas.drawPath(fullPath, windPaint);

      final segmentCount = streamline.length - 1;
      if (segmentCount < 3) {
        continue;
      }
      final headProgress =
          animateWind ? (animationPhase + seed.seed).remainder(1.0) : 0.58;
      final headIndex = (1 + (headProgress * (streamline.length - 2)))
          .round()
          .clamp(2, streamline.length - 1)
          .toInt();
      final tailIndex = math
          .max(
            0,
            headIndex - math.max(3, (streamline.length * 0.45).round()),
          )
          .toInt();
      final highlightPoints = streamline.sublist(tailIndex, headIndex + 1);
      final highlightPath = _buildWindPath(highlightPoints, center, mapRadius);

      outlinePaint
        ..color = lineColor.withAlpha((alpha * 0.34).round())
        ..strokeWidth = _screenStableRadius(4.8, viewScale, minRadius: 1.55);
      windPaint
        ..color = lineColor.withAlpha(alpha)
        ..strokeWidth = _screenStableRadius(2.2, viewScale, minRadius: 0.86);
      corePaint
        ..color = Color.fromARGB(
          (178 + (54 * speedT)).round().clamp(0, 255),
          250,
          252,
          255,
        )
        ..strokeWidth = _screenStableRadius(0.92, viewScale, minRadius: 0.42);

      canvas.drawPath(highlightPath, outlinePaint);
      canvas.drawPath(highlightPath, windPaint);
      canvas.drawPath(highlightPath, corePaint);

      if (highlightPoints.length >= 2) {
        final arrowStart = _projectLatLon(
          center,
          mapRadius,
          highlightPoints[highlightPoints.length - 2].latitude,
          highlightPoints[highlightPoints.length - 2].longitude,
        );
        final arrowEnd = _projectLatLon(
          center,
          mapRadius,
          highlightPoints.last.latitude,
          highlightPoints.last.longitude,
        );
        _paintWindArrowhead(
          canvas,
          start: arrowStart,
          end: arrowEnd,
          color: lineColor.withAlpha((alpha * 0.96).round()),
          speedT: speedT,
        );
      }
    }

    canvas.restore();
  }

  void _paintWeatherOverlayLegend(Canvas canvas) {
    final snapshot = weatherOverlaySnapshot;
    if (snapshot == null) {
      return;
    }

    const minLegendWidth = 240.0;
    const maxLegendWidth = 336.0;
    const horizontalPadding = 12.0;
    const topPadding = 10.0;
    const bottomPadding = 10.0;
    const gapAfterTitle = 10.0;
    const gapAfterBar = 6.0;
    const subtitleReserveWidth = 78.0;
    const minBarWidth = 168.0;
    final stableScale = _screenStableLabelScale(viewScale);
    final titleText = snapshot.unitLabel.isEmpty
        ? snapshot.overlayLabel
        : '${snapshot.overlayLabel} (${_weatherUnitLabelForDisplay(snapshot.unitLabel, includeFahrenheitForCelsius: true)})';
    final subtitleText =
        snapshot.level == 'surface' ? 'Surface' : '${snapshot.level} hPa';
    final minText = _weatherValueForDisplay(
      snapshot.minValue,
      snapshot.unitLabel,
      includeFahrenheitForCelsius: true,
      multilineForFahrenheit: _isCelsiusWeatherUnit(snapshot.unitLabel),
    );
    final maxText = _weatherValueForDisplay(
      snapshot.maxValue,
      snapshot.unitLabel,
      includeFahrenheitForCelsius: true,
      multilineForFahrenheit: _isCelsiusWeatherUnit(snapshot.unitLabel),
    );

    final titlePainter = TextPainter(
      text: TextSpan(
        text: titleText,
        style: const TextStyle(
          color: Color(0xFF112A46),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
    )..layout(
        maxWidth:
            maxLegendWidth - (horizontalPadding * 2) - subtitleReserveWidth,
      );

    final subtitlePainter = TextPainter(
      text: TextSpan(
        text: subtitleText,
        style: const TextStyle(
          color: Color(0xFF335C67),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    )..layout(maxWidth: subtitleReserveWidth);

    final minPainter = TextPainter(
      text: TextSpan(
        text: minText,
        style: const TextStyle(
          color: Color(0xFF335C67),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 120);
    final maxPainter = TextPainter(
      text: TextSpan(
        text: maxText,
        style: const TextStyle(
          color: Color(0xFF335C67),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    )..layout(maxWidth: 120);

    final topSectionWidth = titlePainter.width + 10 + subtitlePainter.width;
    final labelsWidth = minPainter.width + 36 + maxPainter.width;
    final contentWidth = math.max(
      math.max(topSectionWidth, labelsWidth),
      minBarWidth,
    );
    final legendWidth = (contentWidth + (horizontalPadding * 2))
        .clamp(minLegendWidth, maxLegendWidth)
        .toDouble();
    final topSectionHeight =
        math.max(titlePainter.height, subtitlePainter.height);
    final legendHeight = topPadding +
        topSectionHeight +
        gapAfterTitle +
        14 +
        gapAfterBar +
        math.max(minPainter.height, maxPainter.height) +
        bottomPadding;
    final halfWidth = legendWidth / 2;
    final contentLeft = -(halfWidth - horizontalPadding);
    final contentRight = halfWidth - horizontalPadding;
    final titleTop = -legendHeight / 2 + topPadding;
    final barRect = Rect.fromLTWH(
      contentLeft,
      titleTop + topSectionHeight + gapAfterTitle,
      legendWidth - (horizontalPadding * 2),
      14,
    );
    final labelsTop = barRect.bottom + gapAfterBar;
    final anchor = _legendAnchor(
      visibleSceneRect: visibleSceneRect,
      viewScale: viewScale,
      legendWidth: legendWidth,
      legendHeight: legendHeight,
      alignRight: false,
      sceneWidth: projectedScene.size.width,
    );

    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.rotate(-viewRotationRadians);
    canvas.scale(stableScale);

    final background = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: legendWidth,
        height: legendHeight,
      ),
      const Radius.circular(16),
    );
    canvas.drawRRect(
      background,
      Paint()..color = const Color(0xEAF8FBF6),
    );
    canvas.drawRRect(
      background,
      Paint()
        ..color = const Color(0xFFBFCBD5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    titlePainter.paint(canvas, Offset(contentLeft, titleTop));
    subtitlePainter.paint(
      canvas,
      Offset(contentRight - subtitlePainter.width, titleTop),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, const Radius.circular(999)),
      Paint()
        ..shader = ui.Gradient.linear(
          barRect.topLeft,
          barRect.topRight,
          const [
            Color(0xFF7F3FBF),
            Color(0xFF4B3FBF),
            Color(0xFF2C6EE8),
            Color(0xFF2FAE63),
            Color(0xFFF2D13D),
            Color(0xFFF28C28),
            Color(0xFFE63B2E),
          ],
          const [0.0, 0.16, 0.32, 0.5, 0.68, 0.84, 1.0],
        ),
    );

    minPainter.paint(canvas, Offset(contentLeft, labelsTop));
    maxPainter.paint(
      canvas,
      Offset(contentRight - maxPainter.width, labelsTop),
    );

    canvas.restore();
  }

  void _paintCombinedWeatherLegend(Canvas canvas) {
    final overlaySnapshot = weatherOverlaySnapshot;
    final wind = windSnapshot;
    if (overlaySnapshot == null || wind == null) {
      return;
    }

    final windColorDomain = _windColorDomain(wind);
    const minLegendWidth = 252.0;
    const maxLegendWidth = 336.0;
    const horizontalPadding = 12.0;
    const topPadding = 10.0;
    const bottomPadding = 10.0;
    const sectionGap = 12.0;
    const gapAfterTitle = 8.0;
    const gapAfterBar = 6.0;
    const subtitleReserveWidth = 78.0;
    const minBarWidth = 168.0;
    final stableScale = _screenStableLabelScale(viewScale);

    final overlayTitleText = overlaySnapshot.unitLabel.isEmpty
        ? 'Overlay: ${overlaySnapshot.overlayLabel}'
        : 'Overlay: ${overlaySnapshot.overlayLabel} (${_weatherUnitLabelForDisplay(overlaySnapshot.unitLabel, includeFahrenheitForCelsius: true)})';
    final overlaySubtitleText = overlaySnapshot.level == 'surface'
        ? 'Surface'
        : '${overlaySnapshot.level} hPa';
    final overlayMinText = _weatherValueForDisplay(
      overlaySnapshot.minValue,
      overlaySnapshot.unitLabel,
      includeFahrenheitForCelsius: true,
      multilineForFahrenheit: _isCelsiusWeatherUnit(overlaySnapshot.unitLabel),
    );
    final overlayMaxText = _weatherValueForDisplay(
      overlaySnapshot.maxValue,
      overlaySnapshot.unitLabel,
      includeFahrenheitForCelsius: true,
      multilineForFahrenheit: _isCelsiusWeatherUnit(overlaySnapshot.unitLabel),
    );
    final animateTitleText = 'Animate: $weatherAnimationLabel speed (m/s)';
    final animateSubtitleText =
        wind.level == 'surface' ? 'Surface' : '${wind.level} hPa';

    final overlayTitlePainter = TextPainter(
      text: TextSpan(
        text: overlayTitleText,
        style: const TextStyle(
          color: Color(0xFF112A46),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
    )..layout(
        maxWidth:
            maxLegendWidth - (horizontalPadding * 2) - subtitleReserveWidth,
      );
    final overlaySubtitlePainter = TextPainter(
      text: TextSpan(
        text: overlaySubtitleText,
        style: const TextStyle(
          color: Color(0xFF335C67),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    )..layout(maxWidth: subtitleReserveWidth);
    final overlayMinPainter = TextPainter(
      text: TextSpan(
        text: overlayMinText,
        style: const TextStyle(
          color: Color(0xFF335C67),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 120);
    final overlayMaxPainter = TextPainter(
      text: TextSpan(
        text: overlayMaxText,
        style: const TextStyle(
          color: Color(0xFF335C67),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    )..layout(maxWidth: 120);

    final animateTitlePainter = TextPainter(
      text: TextSpan(
        text: animateTitleText,
        style: const TextStyle(
          color: Color(0xFF112A46),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(
        maxWidth:
            maxLegendWidth - (horizontalPadding * 2) - subtitleReserveWidth,
      );
    final animateSubtitlePainter = TextPainter(
      text: TextSpan(
        text: animateSubtitleText,
        style: const TextStyle(
          color: Color(0xFF335C67),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    )..layout(maxWidth: subtitleReserveWidth);
    final animateMinPainter = TextPainter(
      text: TextSpan(
        text: '${windColorDomain.min.toStringAsFixed(1)} m/s',
        style: const TextStyle(
          color: Color(0xFF335C67),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 40);
    final animateMaxPainter = TextPainter(
      text: TextSpan(
        text: '${windColorDomain.max.toStringAsFixed(1)} m/s',
        style: const TextStyle(
          color: Color(0xFF335C67),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    )..layout(maxWidth: 40);

    final overlayContentWidth = math.max(
      math.max(
        overlayTitlePainter.width + 10 + overlaySubtitlePainter.width,
        overlayMinPainter.width + 36 + overlayMaxPainter.width,
      ),
      minBarWidth,
    );
    final animateContentWidth = math.max(
      math.max(
        animateTitlePainter.width + 10 + animateSubtitlePainter.width,
        animateMinPainter.width + 36 + animateMaxPainter.width,
      ),
      minBarWidth,
    );
    final legendWidth = (math.max(overlayContentWidth, animateContentWidth) +
            (horizontalPadding * 2))
        .clamp(minLegendWidth, maxLegendWidth)
        .toDouble();
    final overlaySectionHeight = math.max(
          overlayTitlePainter.height,
          overlaySubtitlePainter.height,
        ) +
        gapAfterTitle +
        14 +
        gapAfterBar +
        math.max(overlayMinPainter.height, overlayMaxPainter.height);
    final animateSectionHeight = math.max(
          animateTitlePainter.height,
          animateSubtitlePainter.height,
        ) +
        gapAfterTitle +
        14 +
        gapAfterBar +
        math.max(animateMinPainter.height, animateMaxPainter.height);
    final legendHeight = topPadding +
        overlaySectionHeight +
        sectionGap +
        animateSectionHeight +
        bottomPadding;
    final halfWidth = legendWidth / 2;
    final contentLeft = -(halfWidth - horizontalPadding);
    final contentRight = halfWidth - horizontalPadding;
    final anchor = _legendAnchor(
      visibleSceneRect: visibleSceneRect,
      viewScale: viewScale,
      legendWidth: legendWidth,
      legendHeight: legendHeight,
      alignRight: false,
      sceneWidth: projectedScene.size.width,
    );

    final overlayTitleTop = -legendHeight / 2 + topPadding;
    final overlayTopSectionHeight = math.max(
      overlayTitlePainter.height,
      overlaySubtitlePainter.height,
    );
    final overlayBarRect = Rect.fromLTWH(
      contentLeft,
      overlayTitleTop + overlayTopSectionHeight + gapAfterTitle,
      legendWidth - (horizontalPadding * 2),
      14,
    );
    final overlayLabelsTop = overlayBarRect.bottom + gapAfterBar;
    final dividerY = overlayLabelsTop +
        math.max(overlayMinPainter.height, overlayMaxPainter.height) +
        (sectionGap / 2);

    final animateTitleTop = dividerY + (sectionGap / 2);
    final animateTopSectionHeight = math.max(
      animateTitlePainter.height,
      animateSubtitlePainter.height,
    );
    final animateBarRect = Rect.fromLTWH(
      contentLeft,
      animateTitleTop + animateTopSectionHeight + gapAfterTitle,
      legendWidth - (horizontalPadding * 2),
      14,
    );
    final animateLabelsTop = animateBarRect.bottom + gapAfterBar;

    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.rotate(-viewRotationRadians);
    canvas.scale(stableScale);

    final background = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: legendWidth,
        height: legendHeight,
      ),
      const Radius.circular(16),
    );
    canvas.drawRRect(background, Paint()..color = const Color(0xEAF8FBF6));
    canvas.drawRRect(
      background,
      Paint()
        ..color = const Color(0xFFBFCBD5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    overlayTitlePainter.paint(canvas, Offset(contentLeft, overlayTitleTop));
    overlaySubtitlePainter.paint(
      canvas,
      Offset(contentRight - overlaySubtitlePainter.width, overlayTitleTop),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(overlayBarRect, const Radius.circular(999)),
      Paint()
        ..shader = ui.Gradient.linear(
          overlayBarRect.topLeft,
          overlayBarRect.topRight,
          const [
            Color(0xFF7F3FBF),
            Color(0xFF4B3FBF),
            Color(0xFF2C6EE8),
            Color(0xFF2FAE63),
            Color(0xFFF2D13D),
            Color(0xFFF28C28),
            Color(0xFFE63B2E),
          ],
          const [0.0, 0.16, 0.32, 0.5, 0.68, 0.84, 1.0],
        ),
    );
    overlayMinPainter.paint(canvas, Offset(contentLeft, overlayLabelsTop));
    overlayMaxPainter.paint(
      canvas,
      Offset(contentRight - overlayMaxPainter.width, overlayLabelsTop),
    );

    canvas.drawLine(
      Offset(contentLeft, dividerY),
      Offset(contentRight, dividerY),
      Paint()
        ..color = const Color(0xFFCFD8DE)
        ..strokeWidth = 1,
    );

    animateTitlePainter.paint(canvas, Offset(contentLeft, animateTitleTop));
    animateSubtitlePainter.paint(
      canvas,
      Offset(contentRight - animateSubtitlePainter.width, animateTitleTop),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(animateBarRect, const Radius.circular(999)),
      Paint()
        ..shader = ui.Gradient.linear(
          animateBarRect.topLeft,
          animateBarRect.topRight,
          const [
            Color(0xFF7F3FBF),
            Color(0xFF4B3FBF),
            Color(0xFF2C6EE8),
            Color(0xFF2FAE63),
            Color(0xFFF2D13D),
            Color(0xFFF28C28),
            Color(0xFFE63B2E),
          ],
          const [0.0, 0.16, 0.32, 0.5, 0.68, 0.84, 1.0],
        ),
    );
    animateMinPainter.paint(canvas, Offset(contentLeft, animateLabelsTop));
    animateMaxPainter.paint(
      canvas,
      Offset(contentRight - animateMaxPainter.width, animateLabelsTop),
    );

    canvas.restore();
  }

  void _paintWindLegend(
    Canvas canvas, {
    required bool alignRight,
  }) {
    final snapshot = windSnapshot;
    if (snapshot == null) {
      return;
    }
    final colorDomain = _windColorDomain(snapshot);

    const legendWidth = 184.0;
    const legendHeight = 66.0;
    const horizontalPadding = 12.0;
    final stableScale = _screenStableLabelScale(viewScale);
    final halfWidth = legendWidth / 2;
    final contentLeft = -(halfWidth - horizontalPadding);
    final contentRight = halfWidth - horizontalPadding;
    final barRect = Rect.fromLTWH(
      contentLeft,
      -2,
      legendWidth - (horizontalPadding * 2),
      14,
    );
    final anchor = _legendAnchor(
      visibleSceneRect: visibleSceneRect,
      viewScale: viewScale,
      legendWidth: legendWidth,
      legendHeight: legendHeight,
      alignRight: alignRight,
      sceneWidth: projectedScene.size.width,
    );

    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.rotate(-viewRotationRadians);
    canvas.scale(stableScale);

    final background = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: legendWidth,
        height: legendHeight,
      ),
      const Radius.circular(16),
    );
    canvas.drawRRect(
      background,
      Paint()..color = const Color(0xEAF8FBF6),
    );
    canvas.drawRRect(
      background,
      Paint()
        ..color = const Color(0xFFBFCBD5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final titlePainter = TextPainter(
      text: TextSpan(
        text: '$weatherAnimationLabel speed (m/s)',
        style: TextStyle(
          color: Color(0xFF112A46),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: legendWidth - (horizontalPadding * 2));
    titlePainter.paint(canvas, Offset(contentLeft, -29));

    final subtitlePainter = TextPainter(
      text: TextSpan(
        text: snapshot.level == 'surface' ? 'Surface' : '${snapshot.level} hPa',
        style: const TextStyle(
          color: Color(0xFF335C67),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 68);
    subtitlePainter.paint(
      canvas,
      Offset(contentRight - subtitlePainter.width, -29),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, const Radius.circular(999)),
      Paint()
        ..shader = ui.Gradient.linear(
          barRect.topLeft,
          barRect.topRight,
          const [
            Color(0xFF7F3FBF),
            Color(0xFF4B3FBF),
            Color(0xFF2C6EE8),
            Color(0xFF2FAE63),
            Color(0xFFF2D13D),
            Color(0xFFF28C28),
            Color(0xFFE63B2E),
          ],
          const [0.0, 0.16, 0.32, 0.5, 0.68, 0.84, 1.0],
        ),
    );

    final minPainter = TextPainter(
      text: TextSpan(
        text: '${colorDomain.min.toStringAsFixed(1)} m/s',
        style: const TextStyle(
          color: Color(0xFF335C67),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 40);
    final maxPainter = TextPainter(
      text: TextSpan(
        text: '${colorDomain.max.toStringAsFixed(1)} m/s',
        style: const TextStyle(
          color: Color(0xFF335C67),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 40);
    minPainter.paint(canvas, Offset(contentLeft, 18));
    maxPainter.paint(canvas, Offset(contentRight - maxPainter.width, 18));

    canvas.restore();
  }

  void _paintAstronomyOverlay(
    Canvas canvas,
    Offset center,
    double mapRadius,
  ) {
    final snapshot = _resolvedAstronomySnapshot();
    if (snapshot == null) {
      return;
    }
    final catalog = skyCatalog;

    canvas.save();
    canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: center, radius: mapRadius)));
    _paintAstronomyLightMesh(canvas, center, mapRadius, snapshot);
    if (catalog != null && (showStars || showConstellations)) {
      _paintStarSky(canvas, center, mapRadius, snapshot, catalog);
    }
    canvas.restore();

    if (showSunPath) {
      _paintAstronomyPath(
        canvas,
        center,
        mapRadius,
        snapshot.sun.path,
        const Color(0xE6F8C85C),
      );
    }
    if (showMoonPath) {
      _paintAstronomyPath(
        canvas,
        center,
        mapRadius,
        snapshot.moon.path,
        const Color(0xCFE4EEF7),
      );
    }
    final visiblePlanets = <String>{
      for (final planetName in visiblePlanetNames) planetName,
    };
    for (final planet in snapshot.planets) {
      if (!visiblePlanets.contains(planet.name)) {
        continue;
      }
      final style =
          _planetVisualStyles[planet.name] ?? _planetVisualStyles.values.first;
      _paintAstronomyPath(
        canvas,
        center,
        mapRadius,
        planet.path,
        style.pathColor,
      );
      _paintAstronomyBody(
        canvas,
        center,
        mapRadius,
        planet.subpoint,
        label: planet.name,
        color: style.bodyColor,
        glowColor: style.glowColor,
        baseRadius: style.baseRadius,
      );
    }

    if (showSunPath) {
      _paintAstronomyBody(
        canvas,
        center,
        mapRadius,
        snapshot.sun.subpoint,
        label: 'Sun',
        color: const Color(0xFFF3B43F),
        glowColor: const Color(0x77FFE28C),
        baseRadius: 10.5,
      );
    }
    if (showMoonPath) {
      _paintAstronomyBody(
        canvas,
        center,
        mapRadius,
        snapshot.moon.subpoint,
        label: snapshot.moon.phaseName ?? 'Moon',
        color: const Color(0xFFF3F8FF),
        glowColor: const Color(0x77DCE9FF),
        baseRadius: 8.8,
        illuminationFraction: snapshot.moon.illuminationFraction,
        lightSourcePoint: snapshot.sun.subpoint,
      );
    }

    if (catalog != null) {
      _paintSelectedAstronomyHighlight(
        canvas,
        center,
        mapRadius,
        snapshot,
        catalog,
      );
    }

    final observer = snapshot.observer;
    if (observer != null) {
      final observerPoint = _projectLatLon(
        center,
        mapRadius,
        observer.latitude,
        observer.longitude,
      );
      final observerPaint = Paint()..color = const Color(0xFF0F2940);
      final observerRadius =
          _screenStableRadius(3.2, viewScale, minRadius: 1.2);
      canvas.drawCircle(observerPoint, observerRadius, observerPaint);

      final observerLabelPainter = TextPainter(
        text: TextSpan(
          text: astronomyObserverName ?? observer.name ?? 'Observer',
          style: TextStyle(
            color: const Color(0xFF10283A),
            fontSize: _markerLabelFontSize(viewScale),
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 140);
      _paintAnchoredPointLabel(
        canvas: canvas,
        anchorPoint: observerPoint,
        labelPainter: observerLabelPainter,
        labelOffsetInScreen: const Offset(14, 14),
        dotRadius: observerRadius,
        dotPaint: observerPaint,
        leaderColor: const Color(0xAA0F2940),
      );
    }
  }

  void _paintStarSky(
    Canvas canvas,
    Offset center,
    double mapRadius,
    AstronomySnapshot snapshot,
    SkyCatalog catalog,
  ) {
    if (showStars) {
      _paintStarField(canvas, center, mapRadius, snapshot, catalog);
    }
    if (showConstellations) {
      _paintConstellationOverlay(canvas, center, mapRadius, snapshot, catalog);
    }
  }

  void _paintStarField(
    Canvas canvas,
    Offset center,
    double mapRadius,
    AstronomySnapshot snapshot,
    SkyCatalog catalog,
  ) {
    for (final star in catalog.stars) {
      final isPolaris = star.id == 'polaris';
      final skyPoint = _projectSkyCoordinate(
        center,
        mapRadius,
        rightAscensionHours: star.rightAscensionHours,
        declinationDegrees: star.declinationDegrees,
        siderealDegrees: snapshot.greenwichSiderealDegrees,
      );
      final nightVisibility = _nightSkyVisibility(
        snapshot,
        latitude: star.declinationDegrees,
        longitude: _skyLongitudeForSnapshot(
          star.rightAscensionHours,
          snapshot.greenwichSiderealDegrees,
        ),
      );
      if (nightVisibility <= 0.02) {
        continue;
      }

      final brightness = _starBrightness(star.magnitude) * nightVisibility;
      if (brightness <= 0.03) {
        continue;
      }

      final baseRadius = ui.lerpDouble(
            0.65,
            isPolaris ? 3.6 : 2.25,
            _starBrightness(star.magnitude),
          ) ??
          (isPolaris ? 2.4 : 1.0);
      final starRadius =
          _screenStableRadius(baseRadius, viewScale, minRadius: 0.38);
      final glowRadius = _screenStableRadius(
        baseRadius * (isPolaris ? 3.2 : 2.3),
        viewScale,
        minRadius: isPolaris ? 1.5 : 0.9,
      );
      final glowAlpha =
          ((isPolaris ? 72 : 22) + ((isPolaris ? 120 : 70) * brightness))
              .round()
              .clamp(0, 255);
      final coreAlpha =
          ((isPolaris ? 168 : 52) + ((isPolaris ? 84 : 180) * brightness))
              .round()
              .clamp(0, 255);

      canvas.drawCircle(
        skyPoint,
        glowRadius,
        Paint()
          ..color = isPolaris
              ? Color.fromARGB(glowAlpha.toInt(), 168, 212, 255)
              : Color.fromARGB(glowAlpha.toInt(), 207, 227, 255),
      );
      canvas.drawCircle(
        skyPoint,
        starRadius,
        Paint()
          ..color = isPolaris
              ? Color.fromARGB(coreAlpha.toInt(), 245, 250, 255)
              : Color.fromARGB(coreAlpha.toInt(), 248, 251, 255),
      );

      if (isPolaris && viewScale >= 1.5 && !isInteracting) {
        final labelPainter = TextPainter(
          text: TextSpan(
            text: star.name,
            style: TextStyle(
              color: const Color(0xFF173042),
              fontSize: _layerLabelFontSize('city_major', viewScale),
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 120);
        _paintAnchoredPointLabel(
          canvas: canvas,
          anchorPoint: skyPoint,
          labelPainter: labelPainter,
          labelOffsetInScreen: const Offset(14, -12),
          dotRadius: starRadius,
          dotPaint: Paint()
            ..color = Color.fromARGB(coreAlpha.toInt(), 245, 250, 255),
          leaderColor: const Color(0xAA173042),
        );
      }
    }
  }

  void _paintConstellationOverlay(
    Canvas canvas,
    Offset center,
    double mapRadius,
    AstronomySnapshot snapshot,
    SkyCatalog catalog,
  ) {
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _screenStableRadius(1.45, viewScale, minRadius: 0.58)
      ..isAntiAlias = true;
    final guideUnderlayPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _screenStableRadius(2.7, viewScale, minRadius: 0.95)
      ..isAntiAlias = true;
    const labelVerticalOffset = Offset(0, -12);

    for (final constellation in catalog.constellations) {
      for (final segment in constellation.segments) {
        if (segment.length != 2) {
          continue;
        }
        final startStar = catalog.starsById[segment[0]];
        final endStar = catalog.starsById[segment[1]];
        if (startStar == null || endStar == null) {
          continue;
        }

        final startLongitude = _skyLongitudeForSnapshot(
          startStar.rightAscensionHours,
          snapshot.greenwichSiderealDegrees,
        );
        final endLongitude = _skyLongitudeForSnapshot(
          endStar.rightAscensionHours,
          snapshot.greenwichSiderealDegrees,
        );
        final segmentVisibility = ((_nightSkyVisibility(
                  snapshot,
                  latitude: startStar.declinationDegrees,
                  longitude: startLongitude,
                  forceVisible: showConstellationsFullSky,
                ) +
                _nightSkyVisibility(
                  snapshot,
                  latitude: endStar.declinationDegrees,
                  longitude: endLongitude,
                  forceVisible: showConstellationsFullSky,
                )) /
            2);
        if (segmentVisibility <= 0.04) {
          continue;
        }

        guideUnderlayPaint.color = Color.fromARGB(
          (92 + (104 * segmentVisibility)).round().clamp(0, 255).toInt(),
          15,
          23,
          32,
        );
        linePaint
          ..color = Color.fromARGB(
            (138 + (100 * segmentVisibility)).round().clamp(0, 255).toInt(),
            182,
            136,
            255,
          )
          ..strokeWidth = _screenStableRadius(1.45, viewScale, minRadius: 0.58);

        final startPoint = _projectSkyCoordinate(
          center,
          mapRadius,
          rightAscensionHours: startStar.rightAscensionHours,
          declinationDegrees: startStar.declinationDegrees,
          siderealDegrees: snapshot.greenwichSiderealDegrees,
        );
        final endPoint = _projectSkyCoordinate(
          center,
          mapRadius,
          rightAscensionHours: endStar.rightAscensionHours,
          declinationDegrees: endStar.declinationDegrees,
          siderealDegrees: snapshot.greenwichSiderealDegrees,
        );
        canvas.drawLine(
          startPoint,
          endPoint,
          guideUnderlayPaint,
        );
        canvas.drawLine(
          startPoint,
          endPoint,
          linePaint,
        );
      }

      final labelLongitude = _skyLongitudeForSnapshot(
        constellation.labelRightAscensionHours,
        snapshot.greenwichSiderealDegrees,
      );
      final labelVisibility = _nightSkyVisibility(
        snapshot,
        latitude: constellation.labelDeclinationDegrees,
        longitude: labelLongitude,
        forceVisible: showConstellationsFullSky,
      );
      if (labelVisibility <= 0.08) {
        continue;
      }

      final labelPainter = TextPainter(
        text: TextSpan(
          text: constellation.name,
          style: TextStyle(
            color: const Color(0xFF173042),
            fontSize: _layerLabelFontSize('city_major', viewScale),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.15,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 120);

      final labelCenter = _projectSkyCoordinate(
            center,
            mapRadius,
            rightAscensionHours: constellation.labelRightAscensionHours,
            declinationDegrees: constellation.labelDeclinationDegrees,
            siderealDegrees: snapshot.greenwichSiderealDegrees,
          ) +
          _screenOffsetToScene(labelVerticalOffset, viewScale);
      _paintUprightLabel(
        canvas: canvas,
        center: labelCenter,
        labelPainter: labelPainter,
      );
    }
  }

  void _paintSelectedAstronomyHighlight(
    Canvas canvas,
    Offset center,
    double mapRadius,
    AstronomySnapshot snapshot,
    SkyCatalog catalog,
  ) {
    final selection = selectedAstronomy;
    if (selection == null) {
      return;
    }
    if (selection.kind == _AstronomySelectionKind.star && !showStars) {
      return;
    }
    if (selection.kind == _AstronomySelectionKind.constellation &&
        !showConstellations) {
      return;
    }

    if (selection.kind == _AstronomySelectionKind.star) {
      final star = catalog.starsById[selection.id];
      if (star == null) {
        return;
      }
      final starPoint = _projectSkyCoordinate(
        center,
        mapRadius,
        rightAscensionHours: star.rightAscensionHours,
        declinationDegrees: star.declinationDegrees,
        siderealDegrees: snapshot.greenwichSiderealDegrees,
      );
      canvas.drawCircle(
        starPoint,
        _screenStableRadius(10.0, viewScale, minRadius: 4.2),
        Paint()..color = const Color(0x449B6DFF),
      );
      canvas.drawCircle(
        starPoint,
        _screenStableRadius(6.0, viewScale, minRadius: 2.4),
        Paint()
          ..color = const Color(0xFF9B6DFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _screenStableRadius(1.6, viewScale, minRadius: 0.7),
      );
      return;
    }

    final matches =
        catalog.constellations.where((entry) => entry.id == selection.id);
    if (matches.isEmpty) {
      return;
    }
    final constellation = matches.first;
    final highlightPaint = Paint()
      ..color = const Color(0xFF9B6DFF)
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _screenStableRadius(2.2, viewScale, minRadius: 0.95)
      ..isAntiAlias = true;
    for (final segment in constellation.segments) {
      if (segment.length != 2) {
        continue;
      }
      final startStar = catalog.starsById[segment[0]];
      final endStar = catalog.starsById[segment[1]];
      if (startStar == null || endStar == null) {
        continue;
      }
      canvas.drawLine(
        _projectSkyCoordinate(
          center,
          mapRadius,
          rightAscensionHours: startStar.rightAscensionHours,
          declinationDegrees: startStar.declinationDegrees,
          siderealDegrees: snapshot.greenwichSiderealDegrees,
        ),
        _projectSkyCoordinate(
          center,
          mapRadius,
          rightAscensionHours: endStar.rightAscensionHours,
          declinationDegrees: endStar.declinationDegrees,
          siderealDegrees: snapshot.greenwichSiderealDegrees,
        ),
        highlightPaint,
      );
    }
    for (final starId in constellation.starIds) {
      final star = catalog.starsById[starId];
      if (star == null) {
        continue;
      }
      canvas.drawCircle(
        _projectSkyCoordinate(
          center,
          mapRadius,
          rightAscensionHours: star.rightAscensionHours,
          declinationDegrees: star.declinationDegrees,
          siderealDegrees: snapshot.greenwichSiderealDegrees,
        ),
        _screenStableRadius(4.4, viewScale, minRadius: 1.8),
        Paint()..color = const Color(0x559B6DFF),
      );
    }
  }

  void _paintSelectedAstronomyCallout(
    Canvas canvas,
    Offset center,
    double mapRadius,
  ) {
    final selection = selectedAstronomy;
    final snapshot = astronomySnapshot;
    final catalog = skyCatalog;
    if (selection == null || snapshot == null || catalog == null) {
      return;
    }
    if (selection.kind == _AstronomySelectionKind.star && !showStars) {
      return;
    }
    if (selection.kind == _AstronomySelectionKind.constellation &&
        !showConstellations) {
      return;
    }

    Offset? anchorPoint;
    if (selection.kind == _AstronomySelectionKind.star) {
      final star = catalog.starsById[selection.id];
      if (star == null) {
        return;
      }
      anchorPoint = _projectSkyCoordinate(
        center,
        mapRadius,
        rightAscensionHours: star.rightAscensionHours,
        declinationDegrees: star.declinationDegrees,
        siderealDegrees: snapshot.greenwichSiderealDegrees,
      );
    } else {
      final matches =
          catalog.constellations.where((entry) => entry.id == selection.id);
      if (matches.isEmpty) {
        return;
      }
      final constellation = matches.first;
      anchorPoint = _projectSkyCoordinate(
        center,
        mapRadius,
        rightAscensionHours: constellation.labelRightAscensionHours,
        declinationDegrees: constellation.labelDeclinationDegrees,
        siderealDegrees: snapshot.greenwichSiderealDegrees,
      );
    }

    final zodiacGlyph = selection.kind == _AstronomySelectionKind.constellation
        ? _zodiacGlyphs[selection.id]
        : null;
    final glyphPainter = zodiacGlyph == null
        ? null
        : (TextPainter(
            text: TextSpan(
              text: zodiacGlyph,
              style: TextStyle(
                color: const Color(0xFF6E4BD8),
                fontSize:
                    (_layerLabelFontSize('continent', viewScale) + 8) * 0.75,
                fontWeight: FontWeight.w900,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: 80));
    final labelCenter = anchorPoint +
        _screenOffsetToScene(
          selection.kind == _AstronomySelectionKind.constellation
              ? const Offset(30, -6)
              : const Offset(16, -18),
          viewScale,
        );
    if (selection.kind == _AstronomySelectionKind.constellation &&
        glyphPainter != null) {
      _paintUprightLabel(
        canvas: canvas,
        center: labelCenter,
        labelPainter: glyphPainter,
      );
      return;
    }

    final labelPainter = TextPainter(
      text: TextSpan(
        text: selection.displayName,
        style: TextStyle(
          color: const Color(0xFF0F1720),
          fontSize: _layerLabelFontSize('state', viewScale),
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 190);
    final background = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: labelCenter,
        width: labelPainter.width + 18,
        height: labelPainter.height + 10,
      ),
      const Radius.circular(999),
    );
    _paintUprightLabel(
      canvas: canvas,
      center: labelCenter,
      labelPainter: labelPainter,
      background: background,
      backgroundPaint: Paint()..color = const Color(0xECF8F3E8),
    );
  }

  Offset _projectSkyCoordinate(
    Offset center,
    double mapRadius, {
    required double rightAscensionHours,
    required double declinationDegrees,
    required double siderealDegrees,
  }) {
    return _projectSkyCoordinatePoint(
      center,
      mapRadius,
      rightAscensionHours: rightAscensionHours,
      declinationDegrees: declinationDegrees,
      siderealDegrees: siderealDegrees,
    );
  }

  double _skyLongitudeForSnapshot(
    double rightAscensionHours,
    double siderealDegrees,
  ) {
    return _skyLongitudeDegrees(rightAscensionHours, siderealDegrees);
  }

  double _starBrightness(double magnitude) {
    final clampedMagnitude = magnitude.clamp(-1.5, 5.5).toDouble();
    final normalized = 1.0 - ((clampedMagnitude + 1.5) / 7.0);
    return normalized.clamp(0.1, 1.0);
  }

  double _nightSkyVisibility(
    AstronomySnapshot snapshot, {
    required double latitude,
    required double longitude,
    bool forceVisible = false,
  }) {
    if (forceVisible) {
      return 1.0;
    }
    final sunIncidence = _hemisphereIncidence(
      latitude,
      longitude,
      snapshot.sun.subpoint.latitude,
      snapshot.sun.subpoint.longitude,
    );
    final daylightBlend = _smoothStep(-0.18, 0.06, sunIncidence);
    final moonIncidence = _hemisphereIncidence(
      latitude,
      longitude,
      snapshot.moon.subpoint.latitude,
      snapshot.moon.subpoint.longitude,
    ).clamp(0.0, 1.0);
    final moonStrength = (snapshot.moon.illuminationFraction ?? 0) * 0.18;
    final moonWashout = moonStrength * moonIncidence * (1.0 - daylightBlend);
    return (1.0 - daylightBlend - moonWashout).clamp(0.0, 1.0).toDouble();
  }

  void _paintAstronomyLightMesh(
    Canvas canvas,
    Offset center,
    double mapRadius,
    AstronomySnapshot snapshot,
  ) {
    final sunLatitude = snapshot.sun.subpoint.latitude;
    final sunLongitude = snapshot.sun.subpoint.longitude;
    final moonLatitude = snapshot.moon.subpoint.latitude;
    final moonLongitude = snapshot.moon.subpoint.longitude;
    final moonStrength =
        showMoonPath ? (snapshot.moon.illuminationFraction ?? 0) * 0.22 : 0.0;
    final latitudeStep = isInteracting ? 5.0 : 2.5;
    final longitudeStep = isInteracting ? 5.0 : 2.5;
    final positions = <Offset>[];
    final colors = <Color>[];
    final indices = <int>[];

    for (double latitude = 90.0; latitude > -90.0; latitude -= latitudeStep) {
      final nextLatitude = math.max(-90.0, latitude - latitudeStep);
      for (double longitude = -180.0;
          longitude < 180.0;
          longitude += longitudeStep) {
        final nextLongitude = math.min(180.0, longitude + longitudeStep);
        final topLeft = _projectLatLon(center, mapRadius, latitude, longitude);
        final topRight = _projectLatLon(
          center,
          mapRadius,
          latitude,
          nextLongitude,
        );
        final bottomRight = _projectLatLon(
          center,
          mapRadius,
          nextLatitude,
          nextLongitude,
        );
        final bottomLeft = _projectLatLon(
          center,
          mapRadius,
          nextLatitude,
          longitude,
        );

        final baseIndex = positions.length;
        positions.addAll([topLeft, topRight, bottomRight, bottomLeft]);
        colors.addAll([
          _astronomyShadeColor(
            latitude: latitude,
            longitude: longitude,
            sunLatitude: sunLatitude,
            sunLongitude: sunLongitude,
            moonLatitude: moonLatitude,
            moonLongitude: moonLongitude,
            moonStrength: moonStrength,
          ),
          _astronomyShadeColor(
            latitude: latitude,
            longitude: nextLongitude,
            sunLatitude: sunLatitude,
            sunLongitude: sunLongitude,
            moonLatitude: moonLatitude,
            moonLongitude: moonLongitude,
            moonStrength: moonStrength,
          ),
          _astronomyShadeColor(
            latitude: nextLatitude,
            longitude: nextLongitude,
            sunLatitude: sunLatitude,
            sunLongitude: sunLongitude,
            moonLatitude: moonLatitude,
            moonLongitude: moonLongitude,
            moonStrength: moonStrength,
          ),
          _astronomyShadeColor(
            latitude: nextLatitude,
            longitude: longitude,
            sunLatitude: sunLatitude,
            sunLongitude: sunLongitude,
            moonLatitude: moonLatitude,
            moonLongitude: moonLongitude,
            moonStrength: moonStrength,
          ),
        ]);
        indices.addAll([
          baseIndex,
          baseIndex + 1,
          baseIndex + 2,
          baseIndex,
          baseIndex + 2,
          baseIndex + 3,
        ]);
      }
    }

    final shadePaint = Paint()..isAntiAlias = true;
    canvas.drawVertices(
      ui.Vertices(
        ui.VertexMode.triangles,
        positions,
        colors: colors,
        indices: indices,
      ),
      BlendMode.srcOver,
      shadePaint,
    );
  }

  Color _astronomyShadeColor({
    required double latitude,
    required double longitude,
    required double sunLatitude,
    required double sunLongitude,
    required double moonLatitude,
    required double moonLongitude,
    required double moonStrength,
  }) {
    final sunIncidence = _hemisphereIncidence(
      latitude,
      longitude,
      sunLatitude,
      sunLongitude,
    );
    final moonIncidence = _hemisphereIncidence(
      latitude,
      longitude,
      moonLatitude,
      moonLongitude,
    );
    final daylightBlend = _smoothStep(-0.18, 0.12, sunIncidence);
    double darkness = ui.lerpDouble(0.66, 0.03, daylightBlend) ?? 0.34;
    darkness -= moonStrength *
        moonIncidence.clamp(0.0, 1.0).toDouble() *
        (1.0 - daylightBlend);
    darkness = darkness.clamp(0.02, 0.68).toDouble();
    return Color.lerp(
          const Color(0x00000000),
          const Color(0xCC07162B),
          darkness,
        ) ??
        const Color(0x6607162B);
  }

  double _smoothStep(double edge0, double edge1, double value) {
    final t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0).toDouble();
    return t * t * (3.0 - (2.0 * t));
  }

  void _paintAstronomyPath(
    Canvas canvas,
    Offset center,
    double mapRadius,
    List<PlaceMarker> points,
    Color color,
  ) {
    if (points.length < 2) {
      return;
    }
    final path = Path();
    final first = _project(center, mapRadius, points.first.x, points.first.y);
    path.moveTo(first.dx, first.dy);
    for (final point in points.skip(1)) {
      final projected = _project(center, mapRadius, point.x, point.y);
      path.lineTo(projected.dx, projected.dy);
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _screenStableRadius(1.8, viewScale, minRadius: 0.7)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(path, paint);
  }

  void _paintAstronomyBody(
    Canvas canvas,
    Offset center,
    double mapRadius,
    PlaceMarker point, {
    required String label,
    required Color color,
    required Color glowColor,
    required double baseRadius,
    double? illuminationFraction,
    PlaceMarker? lightSourcePoint,
  }) {
    final projected = _project(center, mapRadius, point.x, point.y);
    final pulse =
        0.78 + (0.22 * math.sin(astronomyPulseAnimation.value * math.pi * 2));
    final glowPaint = Paint()..color = glowColor;
    final bodyPaint = Paint()..color = color;
    final glowRadius = _screenStableRadius(
      baseRadius * (1.8 + pulse),
      viewScale,
      minRadius: 3.0,
    );
    final bodyRadius =
        _screenStableRadius(baseRadius, viewScale, minRadius: 1.8);
    canvas.drawCircle(projected, glowRadius, glowPaint);
    if (illuminationFraction != null && lightSourcePoint != null) {
      final shadowPaint = Paint()
        ..shader = ui.Gradient.radial(
          projected.translate(-bodyRadius * 0.22, -bodyRadius * 0.24),
          bodyRadius * 1.28,
          const [
            Color(0xFFB9C3D2),
            Color(0xFF7F8A9B),
            Color(0xFF5F697B),
          ],
          const [0.0, 0.62, 1.0],
        );
      canvas.drawCircle(projected, bodyRadius, shadowPaint);

      final lightSourceProjected = _project(
        center,
        mapRadius,
        lightSourcePoint.x,
        lightSourcePoint.y,
      );
      final lightAngle = math.atan2(
        lightSourceProjected.dy - projected.dy,
        lightSourceProjected.dx - projected.dx,
      );
      final litPath = _buildMoonLitPath(
        bodyRadius,
        illuminationFraction,
      );
      if (!litPath.getBounds().isEmpty) {
        canvas.save();
        canvas.translate(projected.dx, projected.dy);
        canvas.rotate(lightAngle);
        final litPaint = Paint()
          ..shader = ui.Gradient.radial(
            Offset(-bodyRadius * 0.18, -bodyRadius * 0.2),
            bodyRadius * 1.22,
            [
              const Color(0xFFFFFFFF),
              color,
              const Color(0xFFE0E8F3),
            ],
            const [0.0, 0.55, 1.0],
          );
        canvas.drawPath(litPath, litPaint);
        canvas.restore();
      }

      final rimPaint = Paint()
        ..color = const Color(0xD9F4F8FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.1, bodyRadius * 0.1);
      canvas.drawCircle(projected, bodyRadius, rimPaint);
    } else {
      canvas.drawCircle(projected, bodyRadius, bodyPaint);
    }

    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: const Color(0xFF10283A),
          fontSize: _markerLabelFontSize(viewScale),
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 160);
    _paintAnchoredPointLabel(
      canvas: canvas,
      anchorPoint: projected,
      labelPainter: labelPainter,
      labelOffsetInScreen: const Offset(16, -18),
      dotRadius: bodyRadius,
      dotPaint: bodyPaint,
      leaderColor: const Color(0xAA10283A),
    );
  }

  Path _buildMoonLitPath(double radius, double illuminationFraction) {
    final clampedIllumination = illuminationFraction.clamp(0.0, 1.0).toDouble();
    if (clampedIllumination <= 0.001) {
      return Path();
    }
    if (clampedIllumination >= 0.999) {
      return Path()
        ..addOval(Rect.fromCircle(center: Offset.zero, radius: radius));
    }

    final terminatorScale = 1.0 - (2.0 * clampedIllumination);
    const sampleCount = 48;
    final terminatorPoints = <Offset>[];
    final rimPoints = <Offset>[];

    for (var index = 0; index <= sampleCount; index += 1) {
      final t = index / sampleCount;
      final y = ui.lerpDouble(-radius, radius, t) ?? 0.0;
      final rimX = math.sqrt(math.max(0.0, (radius * radius) - (y * y)));
      terminatorPoints.add(Offset(terminatorScale * rimX, y));
      rimPoints.add(Offset(rimX, y));
    }

    final path = Path()
      ..moveTo(
        terminatorPoints.first.dx,
        terminatorPoints.first.dy,
      );
    for (final point in terminatorPoints.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    for (final point in rimPoints.reversed) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    return path;
  }

  void _paintLayerLabels(
    Canvas canvas,
    Offset center,
    double radius,
    Path landClipPath,
    List<List<Offset>> projectedLandRings,
  ) {
    final scenePadding = 26 / viewScale.clamp(1.0, 24.0);
    final paddedVisibleSceneRect = visibleSceneRect.inflate(scenePadding);
    final placedLabelRects = <Rect>[];

    for (var labelIndex = 0; labelIndex < labels.length; labelIndex += 1) {
      final label = labels[labelIndex];
      if (isInteracting &&
          (label.layer == 'capital_world' ||
              label.layer == 'city_world' ||
              label.layer == 'city_regional' ||
              label.layer == 'city_local' ||
              label.layer == 'city_detail')) {
        continue;
      }
      if (label.minScale > labelScale) {
        continue;
      }

      final point = labelIndex < labelAnchorPoints.length
          ? labelAnchorPoints[labelIndex]
          : _resolveDisplayPoint(
              originalPoint: _project(center, radius, label.x, label.y),
              landClipPath: landClipPath,
              projectedLandRings: projectedLandRings,
              maxSnapDistanceInScreen:
                  _isPointLabelLayer(label.layer) ? 44 : 26,
            );
      final isCityLabel = _isCityLayer(label.layer);
      final isCapitalLabel = _isCapitalLayer(label.layer);
      final labelFontSize = _layerLabelFontSize(label.layer, viewScale);
      final style = switch (label.layer) {
        'continent' => TextStyle(
            color: Color(0xFF10283A),
            fontSize: labelFontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        'country' => TextStyle(
            color: Color(0xFF173042),
            fontSize: labelFontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        'state' => TextStyle(
            color: Color(0xFF173042),
            fontSize: labelFontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.15,
          ),
        'capital_world' => TextStyle(
            color: Color(0xFF173042),
            fontSize: labelFontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.15,
          ),
        'city_world' => TextStyle(
            color: Color(0xFF173042),
            fontSize: labelFontSize,
            fontWeight: FontWeight.w700,
          ),
        'city_major' => TextStyle(
            color: Color(0xFF173042),
            fontSize: labelFontSize,
            fontWeight: FontWeight.w800,
          ),
        'city_regional' => TextStyle(
            color: Color(0xFF173042),
            fontSize: labelFontSize,
            fontWeight: FontWeight.w700,
          ),
        'city_local' => TextStyle(
            color: Color(0xFF173042),
            fontSize: labelFontSize,
            fontWeight: FontWeight.w700,
          ),
        'city_detail' => TextStyle(
            color: Color(0xFF173042),
            fontSize: labelFontSize,
            fontWeight: FontWeight.w700,
          ),
        _ => TextStyle(
            color: Color(0xFF173042),
            fontSize: labelFontSize,
            fontWeight: FontWeight.w700,
          ),
      };

      final maxWidth = switch (label.layer) {
        'continent' => 170.0,
        'capital_world' => 120.0,
        'city_world' => 110.0,
        _ => 130.0,
      };
      final textPainter = TextPainter(
        text: TextSpan(text: label.name, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);

      final collisionRect = _labelCollisionRect(
        point: point,
        label: label,
        textPainter: textPainter,
      );
      if (!collisionRect.overlaps(paddedVisibleSceneRect)) {
        continue;
      }
      final hasCollision = placedLabelRects.any(
        (placedRect) => placedRect.overlaps(collisionRect),
      );
      if (hasCollision) {
        continue;
      }
      placedLabelRects
          .add(collisionRect.inflate(2 / viewScale.clamp(1.0, 24.0)));

      if (isCapitalLabel) {
        final starRadius = _capitalLabelStarRadius(viewScale);
        final starPath = _buildStarPath(point, starRadius);
        final starFillPaint = Paint()..color = const Color(0xFFF2C14E);
        final starStrokePaint = Paint()
          ..color = const Color(0xFF173042)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _screenStableRadius(0.8, viewScale, minRadius: 0.35);
        canvas.drawPath(starPath, starFillPaint);
        canvas.drawPath(starPath, starStrokePaint);
        _paintAnchoredPointLabel(
          canvas: canvas,
          anchorPoint: point,
          labelPainter: textPainter,
          labelOffsetInScreen: const Offset(12, -12),
          dotRadius: starRadius,
          dotPaint: starFillPaint,
          leaderColor: const Color(0xAA173042),
        );
        continue;
      }

      if (isCityLabel) {
        final cityDotRadius = _cityLabelDotRadius(label.layer, viewScale);
        final cityDotPaint = Paint()..color = const Color(0xFF173042);
        canvas.drawCircle(point, cityDotRadius, cityDotPaint);
        _paintAnchoredPointLabel(
          canvas: canvas,
          anchorPoint: point,
          labelPainter: textPainter,
          labelOffsetInScreen: const Offset(11, -11),
          dotRadius: cityDotRadius,
          dotPaint: cityDotPaint,
          leaderColor: const Color(0xAA173042),
        );
        continue;
      }

      _paintUprightLabel(
        canvas: canvas,
        center: point,
        labelPainter: textPainter,
      );
    }
  }

  Rect _labelCollisionRect({
    required Offset point,
    required MapLabel label,
    required TextPainter textPainter,
  }) {
    final stableScale = _screenStableLabelScale(viewScale);
    final labelSize = Size(
      textPainter.width * stableScale,
      textPainter.height * stableScale,
    );
    if (_isCapitalLayer(label.layer)) {
      final offset = _screenOffsetToScene(const Offset(12, -12), viewScale);
      final labelCenter = point + offset;
      final textRect = Rect.fromCenter(
        center: labelCenter,
        width: labelSize.width,
        height: labelSize.height,
      );
      final markerRect = Rect.fromCircle(
        center: point,
        radius: _capitalLabelStarRadius(viewScale) + (2 / viewScale),
      );
      return textRect.expandToInclude(markerRect);
    }
    if (_isCityLayer(label.layer)) {
      final offset = _screenOffsetToScene(const Offset(11, -11), viewScale);
      final labelCenter = point + offset;
      final textRect = Rect.fromCenter(
        center: labelCenter,
        width: labelSize.width,
        height: labelSize.height,
      );
      final markerRect = Rect.fromCircle(
        center: point,
        radius: _cityLabelDotRadius(label.layer, viewScale) + (1.5 / viewScale),
      );
      return textRect.expandToInclude(markerRect);
    }
    return Rect.fromCenter(
      center: point,
      width: labelSize.width,
      height: labelSize.height,
    );
  }

  void _paintMeasurementOverlay(
    Canvas canvas,
    Offset center,
    double radius,
  ) {
    if (routePoints.every((point) => point == null)) {
      return;
    }

    final routePaint = Paint()
      ..color = const Color(0xFFF77F00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _screenStableRadius(2.4, viewScale, minRadius: 0.85);

    for (var index = 0; index < routePoints.length - 1; index += 1) {
      final current = routePoints[index];
      final next = routePoints[index + 1];
      if (current == null || next == null) {
        continue;
      }

      final currentPoint = _project(center, radius, current.x, current.y);
      final nextPoint = _project(center, radius, next.x, next.y);
      canvas.drawLine(currentPoint, nextPoint, routePaint);
    }

    for (var index = 0; index < routePoints.length; index += 1) {
      final routePoint = routePoints[index];
      if (routePoint == null) {
        continue;
      }

      final projected = _project(center, radius, routePoint.x, routePoint.y);
      _paintMeasurementPoint(
        canvas: canvas,
        center: projected,
        label: '${index + 1}',
        color: index == 0
            ? const Color(0xFF0B7285)
            : index == routePoints.length - 1
                ? const Color(0xFF9B2226)
                : const Color(0xFF7A5C00),
      );
    }
  }

  void _paintMeasurementPoint({
    required Canvas canvas,
    required Offset center,
    required String label,
    required Color color,
  }) {
    final haloPaint = Paint()..color = color.withAlpha(60);
    final pointPaint = Paint()..color = color;
    final haloRadius = _screenStableRadius(8.0, viewScale, minRadius: 3.0);
    final pointRadius = _screenStableRadius(4.0, viewScale, minRadius: 1.5);
    canvas.drawCircle(center, haloRadius, haloPaint);
    canvas.drawCircle(center, pointRadius, pointPaint);

    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: const Color(0xFFF8F3E8),
          fontSize: _markerLabelFontSize(viewScale),
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelCenter =
        center + _screenOffsetToScene(const Offset(0, -16), viewScale);
    final labelBackground = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: labelCenter,
        width: labelPainter.width + 10,
        height: labelPainter.height + 5,
      ),
      const Radius.circular(999),
    );
    final labelBackgroundPaint = Paint()..color = color;
    _paintUprightLabel(
      canvas: canvas,
      center: labelCenter,
      labelPainter: labelPainter,
      background: labelBackground,
      backgroundPaint: labelBackgroundPaint,
    );
  }

  void _paintAnchoredPointLabel({
    required Canvas canvas,
    required Offset anchorPoint,
    required TextPainter labelPainter,
    required Offset labelOffsetInScreen,
    required double dotRadius,
    required Paint dotPaint,
    required Color leaderColor,
  }) {
    final labelCenter =
        anchorPoint + _screenOffsetToScene(labelOffsetInScreen, viewScale);
    final leaderPaint = Paint()
      ..color = leaderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _screenStableRadius(0.9, viewScale, minRadius: 0.5);

    canvas.drawLine(
      anchorPoint +
          _screenOffsetToScene(Offset(dotRadius, -dotRadius), viewScale),
      labelCenter + _screenOffsetToScene(const Offset(-4, 4), viewScale),
      leaderPaint,
    );

    _paintUprightLabel(
      canvas: canvas,
      center: labelCenter,
      labelPainter: labelPainter,
    );
  }

  void _paintUprightLabel({
    required Canvas canvas,
    required Offset center,
    required TextPainter labelPainter,
    RRect? background,
    Paint? backgroundPaint,
  }) {
    final labelOffset = Offset(
      center.dx - (labelPainter.width / 2),
      center.dy - (labelPainter.height / 2),
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-viewRotationRadians);
    canvas.scale(_screenStableLabelScale(viewScale));
    canvas.translate(-center.dx, -center.dy);
    if (background != null && backgroundPaint != null) {
      canvas.drawRRect(background, backgroundPaint);
    }
    _paintOutlinedText(canvas, labelPainter, labelOffset);
    canvas.restore();
  }

  void _paintOutlinedText(
    Canvas canvas,
    TextPainter labelPainter,
    Offset labelOffset,
  ) {
    final text = labelPainter.text;
    if (text is! TextSpan || text.style == null) {
      labelPainter.paint(canvas, labelOffset);
      return;
    }

    final style = text.style!;
    final outlineSpan = TextSpan(
      text: text.text,
      style: style.copyWith(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = const Color(0xEAF8FBF6),
      ),
      children: text.children,
    );
    final outlinePainter = TextPainter(
      text: outlineSpan,
      textDirection: TextDirection.ltr,
      maxLines: labelPainter.maxLines,
      ellipsis: labelPainter.ellipsis,
      textAlign: labelPainter.textAlign,
      textWidthBasis: labelPainter.textWidthBasis,
    )..layout(maxWidth: labelPainter.width + 2);

    outlinePainter.paint(canvas, labelOffset);
    labelPainter.paint(canvas, labelOffset);
  }

  @override
  bool shouldRepaint(covariant _FlatWorldPainter oldDelegate) {
    return oldDelegate.projectedScene != projectedScene ||
        oldDelegate.visibleSceneRect != visibleSceneRect ||
        oldDelegate.selectedShape != selectedShape ||
        oldDelegate.selectedAstronomy != selectedAstronomy ||
        oldDelegate.markers != markers ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.gridStepDegrees != gridStepDegrees ||
        oldDelegate.edgeRenderMode != edgeRenderMode ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.showShapeLabels != showShapeLabels ||
        oldDelegate.showStateBoundaries != showStateBoundaries ||
        oldDelegate.previousAstronomySnapshot != previousAstronomySnapshot ||
        oldDelegate.astronomySnapshot != astronomySnapshot ||
        oldDelegate.skyCatalog != skyCatalog ||
        oldDelegate.showSunPath != showSunPath ||
        oldDelegate.showMoonPath != showMoonPath ||
        oldDelegate.showStars != showStars ||
        oldDelegate.showConstellations != showConstellations ||
        oldDelegate.showConstellationsFullSky != showConstellationsFullSky ||
        oldDelegate.windSnapshot != windSnapshot ||
        oldDelegate.showWindAnimation != showWindAnimation ||
        oldDelegate.showWindOverlay != showWindOverlay ||
        oldDelegate.weatherAnimationLabel != weatherAnimationLabel ||
        oldDelegate.weatherOverlaySnapshot != weatherOverlaySnapshot ||
        oldDelegate.showWeatherOverlay != showWeatherOverlay ||
        oldDelegate.animateWind != animateWind ||
        !listEquals(oldDelegate.visiblePlanetNames, visiblePlanetNames) ||
        oldDelegate.astronomyObserverName != astronomyObserverName ||
        oldDelegate.routePoints != routePoints ||
        oldDelegate.labels != labels ||
        oldDelegate.showTimeZones != showTimeZones ||
        oldDelegate.useRealTimeZones != useRealTimeZones ||
        oldDelegate.labelScale != labelScale ||
        oldDelegate.viewScale != viewScale ||
        oldDelegate.viewRotationRadians != viewRotationRadians ||
        oldDelegate.isInteracting != isInteracting;
  }
}
