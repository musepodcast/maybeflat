import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/astronomy_snapshot.dart';
import '../models/map_label.dart';
import '../models/map_shape.dart';
import '../models/place_marker.dart';

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
const String _tileCacheVersion = '20260329-ice-ring';

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
  if (longitude == -180 || longitude == -90 || longitude == 0 || longitude == 90) {
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
  final scaledBase =
      densityBase / math.pow(viewScale.clamp(1.0, 8.0), 0.26);
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
  final scaledBase =
      densityBase / math.pow(viewScale.clamp(1.0, 8.0), 0.18);
  return scaledBase.clamp(7.8, 12.0).toDouble();
}

double _screenStableLabelScale(double viewScale) {
  return 1 / viewScale.clamp(1.0, 24.0);
}

double _layerLabelFontSize(String layer, double viewScale) {
  final baseSize = switch (layer) {
    'continent' => 16.5,
    'country' => 13.0,
    'city_major' => 11.0,
    'city_regional' => 10.0,
    'city_local' => 9.0,
    _ => 11.0,
  };
  final minSize = switch (layer) {
    'continent' => 10.2,
    'country' => 8.5,
    'city_major' => 7.5,
    'city_regional' => 6.8,
    'city_local' => 6.2,
    _ => 7.0,
  };
  final scaledSize =
      baseSize / math.pow(viewScale.clamp(1.0, 24.0), 0.18);
  return scaledSize.clamp(minSize, baseSize).toDouble();
}

double _markerLabelFontSize(double viewScale) {
  final scaledSize =
      12 / math.pow(viewScale.clamp(1.0, 24.0), 0.16);
  return scaledSize.clamp(7.2, 12.0).toDouble();
}

double _shapeLabelFontSize(double viewScale) {
  final scaledSize =
      12 / math.pow(viewScale.clamp(1.0, 24.0), 0.16);
  return scaledSize.clamp(7.0, 12.0).toDouble();
}

double _screenStableRadius(
  double baseRadius,
  double viewScale, {
  double minRadius = 1.2,
}) {
  final scaledRadius =
      baseRadius / math.pow(viewScale.clamp(1.0, 24.0), 0.55);
  return scaledRadius.clamp(minRadius, baseRadius).toDouble();
}

bool _isCityLayer(String layer) => layer.startsWith('city');

Offset _screenOffsetToScene(
  Offset offset,
  double viewScale,
) {
  return Offset(offset.dx / viewScale, offset.dy / viewScale);
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

List<Offset> _projectMapRing(
  Offset center,
  double mapRadius,
  MapRing ring,
) {
  return ring.points
      .map((point) => _projectMapPoint(center, mapRadius, point.x, point.y))
      .toList(growable: false);
}

Path _buildProjectedShapePath(List<MapRing> rings, Offset center, double mapRadius) {
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

Offset _nearestPointOnSegmentForDisplay(Offset point, Offset start, Offset end) {
  final segment = end - start;
  final segmentLengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
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
    required this.tileDetailLevel,
    required this.markers,
    required this.shapes,
    required this.labels,
    required this.showGrid,
    required this.gridStepDegrees,
    required this.edgeRenderMode,
    required this.showLabels,
    required this.showShapeLabels,
    required this.showStateBoundaries,
    required this.astronomySnapshot,
    required this.showSunPath,
    required this.showMoonPath,
    required this.astronomyObserverName,
    required this.routePoints,
    required this.activePickLabel,
    required this.onMapPointPicked,
    required this.onInteractionChanged,
    required this.onViewScaleChanged,
  });

  final String tileBaseUrl;
  final String tileDetailLevel;
  final List<PlaceMarker> markers;
  final List<MapShape> shapes;
  final List<MapLabel> labels;
  final bool showGrid;
  final int gridStepDegrees;
  final EdgeRenderMode edgeRenderMode;
  final bool showLabels;
  final bool showShapeLabels;
  final bool showStateBoundaries;
  final AstronomySnapshot? astronomySnapshot;
  final bool showSunPath;
  final bool showMoonPath;
  final String? astronomyObserverName;
  final List<PlaceMarker?> routePoints;
  final String? activePickLabel;
  final ValueChanged<MapTapLocation>? onMapPointPicked;
  final ValueChanged<bool>? onInteractionChanged;
  final ValueChanged<double>? onViewScaleChanged;

  @override
  State<FlatWorldCanvas> createState() => _FlatWorldCanvasState();
}

class _FlatWorldCanvasState extends State<FlatWorldCanvas>
    with SingleTickerProviderStateMixin {
  static const double _minScale = 1;
  static const double _maxScale = 24;
  final TransformationController _transformationController =
      TransformationController();
  late final AnimationController _astronomyAnimationController;
  Timer? _interactionEndTimer;
  double _rotationRadians = 0;
  double _labelScale = 1;
  double _viewScale = 1;
  _GridHoverData? _hoveredGridPoint;
  bool _isInteracting = false;
  final Set<String> _prefetchedTileKeys = <String>{};
  Size? _cachedSceneSize;
  _ProjectedSceneCache? _projectedSceneCache;
  _OverlayAnchorCache? _overlayAnchorCache;

  @override
  void initState() {
    super.initState();
    _astronomyAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _transformationController.addListener(_handleTransformChanged);
  }

  @override
  void didUpdateWidget(covariant FlatWorldCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.shapes, widget.shapes)) {
      _cachedSceneSize = null;
      _overlayAnchorCache = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(36),
          gradient: const RadialGradient(
            colors: [
              Color(0xFFF8F4E7),
              Color(0xFFD3E1E6),
              Color(0xFF8FB2BF),
            ],
            stops: [0.15, 0.6, 1.0],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final projectedScene = _ensureProjectedSceneCache(
                constraints.biggest,
              );
              final overlayAnchors = _ensureOverlayAnchorCache(projectedScene);
              final hasTileBase = widget.shapes.isNotEmpty &&
                  (widget.tileDetailLevel == 'mobile' ||
                      widget.tileDetailLevel == 'desktop' ||
                      widget.tileDetailLevel == 'full');
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
                      child: InteractiveViewer(
                        transformationController: _transformationController,
                        boundaryMargin: const EdgeInsets.all(240),
                        minScale: _minScale,
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
                detailLevel: widget.tileDetailLevel,
                edgeMode: widget.edgeRenderMode,
                tileVersion: _tileCacheVersion,
                viewportSize: constraints.biggest,
                tileZoom: tileZoom,
                tileRange: tileRange,
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
                                      repaint: _astronomyAnimationController,
                                      projectedScene: projectedScene,
                                      markerAnchorPoints: overlayAnchors.markerPoints,
                                      labelAnchorPoints: overlayAnchors.labelPoints,
                                      markers: widget.markers,
                                      labels: widget.labels,
                                      showGrid: widget.showGrid,
                                      gridStepDegrees: widget.gridStepDegrees,
                                      edgeRenderMode: widget.edgeRenderMode,
                                      showLabels: widget.showLabels,
                                      showShapeLabels: widget.showShapeLabels,
                                      showStateBoundaries:
                                          widget.showStateBoundaries,
                                      astronomySnapshot: widget.astronomySnapshot,
                                      showSunPath: widget.showSunPath,
                                      showMoonPath: widget.showMoonPath,
                                      astronomyObserverName:
                                          widget.astronomyObserverName,
                                      routePoints: widget.routePoints,
                                      labelScale: _labelScale,
                                      viewScale: _viewScale,
                                      viewRotationRadians: _rotationRadians,
                                      animationValue:
                                          _astronomyAnimationController.value,
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
                    top: 14,
                    right: 14,
                    child: _ZoomControls(
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
        ),
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

  _OverlayAnchorCache _ensureOverlayAnchorCache(_ProjectedSceneCache projectedScene) {
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
        maxSnapDistanceInScreen: _isCityLayer(label.layer) ? 44 : 26,
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
    final rawZoom = (math.log(viewScale.clamp(1.0, 24.0)) / math.ln2).floor() + 2;
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

  _TileRange _visibleTileRange({
    required Size viewportSize,
    required Rect visibleSceneRect,
    required int tileZoom,
  }) {
    final tileCount = 1 << tileZoom;
    final tileWidth = viewportSize.width / tileCount;
    final tileHeight = viewportSize.height / tileCount;
    final minX =
        (visibleSceneRect.left / tileWidth).floor().clamp(0, tileCount - 1).toInt();
    final maxX =
        (visibleSceneRect.right / tileWidth).ceil().clamp(0, tileCount - 1).toInt();
    final minY =
        (visibleSceneRect.top / tileHeight).floor().clamp(0, tileCount - 1).toInt();
    final maxY =
        (visibleSceneRect.bottom / tileHeight).ceil().clamp(0, tileCount - 1).toInt();
    return _TileRange(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
    );
  }

  void _scheduleTilePrefetch({
    required BuildContext context,
    required int tileZoom,
    required _TileRange tileRange,
  }) {
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
          final key = '${widget.tileDetailLevel}:$edgeMode:$tileZoom:$tileX:$tileY';
          if (_prefetchedTileKeys.contains(key)) {
            continue;
          }
          _prefetchedTileKeys.add(key);
          unawaited(
            precacheImage(
              NetworkImage(
                '${widget.tileBaseUrl}/map/tiles/${widget.tileDetailLevel}/$edgeMode/$tileZoom/$tileX/$tileY.png?v=$_tileCacheVersion',
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
    final mapRadius = radius * 0.94;
    final landEntries = <_ProjectedShapeEntry>[];
    final boundaryEntries = <_ProjectedShapeEntry>[];
    final stateBoundaryEntries = <_ProjectedShapeEntry>[];
    final landClipPath = Path()..fillType = PathFillType.evenOdd;
    final projectedLandRings = <List<Offset>>[];

    for (final shape in shapes) {
      final rings = shape.rings.where((ring) => ring.points.isNotEmpty).toList();
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
      landClipPath: landClipPath,
      projectedLandRings: projectedLandRings,
    );
  }

  void _handleScrollZoom(Offset focalPoint, double scrollDelta) {
    _beginInteraction();
    final currentMatrix = _transformationController.value.clone();
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    final scaleDelta = scrollDelta < 0 ? 1.1 : 0.9;
    final targetScale = (currentScale * scaleDelta).clamp(_minScale, _maxScale);
    final appliedScale = targetScale / currentScale;
    if (appliedScale == 1) {
      return;
    }

    final nextMatrix = currentMatrix
      ..translate(focalPoint.dx, focalPoint.dy)
      ..scale(appliedScale)
      ..translate(-focalPoint.dx, -focalPoint.dy);

    _transformationController.value = nextMatrix;
    _scheduleInteractionEnd();
  }

  void _zoomAtCenter(double scaleDelta) {
    _beginInteraction();
    final currentMatrix = _transformationController.value.clone();
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    final targetScale = (currentScale * scaleDelta).clamp(_minScale, _maxScale);
    final appliedScale = targetScale / currentScale;
    if (appliedScale == 1) {
      return;
    }

    final nextMatrix = currentMatrix..scale(appliedScale);
    _transformationController.value = nextMatrix;
    _scheduleInteractionEnd();
  }

  void _rotateAtCenter(double angleRadians, Offset focalPoint) {
    _beginInteraction();
    final currentMatrix = _transformationController.value.clone();
    final nextMatrix = currentMatrix
      ..translate(focalPoint.dx, focalPoint.dy)
      ..rotateZ(angleRadians)
      ..translate(-focalPoint.dx, -focalPoint.dy);

    setState(() {
      _rotationRadians += angleRadians;
      _transformationController.value = nextMatrix;
    });
    _scheduleInteractionEnd();
  }

  void _resetView() {
      _beginInteraction();
      setState(() {
        _rotationRadians = 0;
        _labelScale = 1;
        _viewScale = 1;
        _transformationController.value = Matrix4.identity();
      });
      _scheduleInteractionEnd();
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
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if (((scale - _labelScale).abs() > 0.04 ||
            (scale - _viewScale).abs() > 0.04) &&
        mounted) {
      setState(() {
        _labelScale = scale;
        _viewScale = scale;
      });
      widget.onViewScaleChanged?.call(scale);
    }
  }

  _GridHoverData? _resolveHoveredGridIntersection(
    Offset viewportPosition,
    Size canvasSize,
  ) {
    final scenePoint = _transformationController.toScene(viewportPosition);
    final center = canvasSize.center(Offset.zero);
    final radius = math.min(canvasSize.width, canvasSize.height) / 2;
    final mapRadius = radius * 0.94;
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
        ? 90 -
            (radiusRatio / _innerWorldRadius) *
                (90 - _innerWorldMinLatitude)
        : _innerWorldMinLatitude -
            ((radiusRatio - _innerWorldRadius) /
                    (_outerRingRadius - _innerWorldRadius)) *
                30;

    final candidateLatitudes = _buildLatitudeGridValues(widget.gridStepDegrees);
    final snappedLatitude = candidateLatitudes.reduce(
      (best, current) =>
          (latitude - current).abs() < (latitude - best).abs()
              ? current
              : best,
    );
    final candidateLongitudes = _buildLongitudeGridValues(widget.gridStepDegrees);
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

  MapTapLocation? _resolveTapLocation(Offset viewportPosition, Size canvasSize) {
    final scenePoint = _transformationController.toScene(viewportPosition);
    final center = canvasSize.center(Offset.zero);
    final radius = math.min(canvasSize.width, canvasSize.height) / 2;
    final mapRadius = radius * 0.94;
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
        ? 90 -
            (radiusRatio / _innerWorldRadius) *
                (90 - _innerWorldMinLatitude)
        : _innerWorldMinLatitude -
            ((radiusRatio - _innerWorldRadius) /
                    (_outerRingRadius - _innerWorldRadius)) *
                30;

    return MapTapLocation(
      latitude: latitude.clamp(-90, 90).toDouble(),
      longitude: rawLongitude.clamp(-180, 180).toDouble(),
      x: normalizedX,
      y: normalizedY,
      zone: radiusRatio <= _innerWorldRadius
          ? 'inner_world'
          : 'antarctic_ring',
    );
  }

  @override
  void dispose() {
    _interactionEndTimer?.cancel();
    _astronomyAnimationController.dispose();
    _transformationController.removeListener(_handleTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onReset,
  });

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
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Zoom in',
            onPressed: onZoomIn,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Zoom out',
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove),
          ),
          IconButton(
            tooltip: 'Rotate left',
            onPressed: onRotateLeft,
            icon: const Icon(Icons.rotate_left),
          ),
          IconButton(
            tooltip: 'Rotate right',
            onPressed: onRotateRight,
            icon: const Icon(Icons.rotate_right),
          ),
          IconButton(
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
    required this.detailLevel,
    required this.edgeMode,
    required this.tileVersion,
    required this.viewportSize,
    required this.tileZoom,
    required this.tileRange,
  });

  final String baseUrl;
  final String detailLevel;
  final EdgeRenderMode edgeMode;
  final String tileVersion;
  final Size viewportSize;
  final int tileZoom;
  final _TileRange tileRange;

  @override
  Widget build(BuildContext context) {
    final tileCount = 1 << tileZoom;
    final tileWidth = viewportSize.width / tileCount;
    final tileHeight = viewportSize.height / tileCount;
    final edgeSlug = _edgeModeSlug(edgeMode);
    final centerTileX = (tileRange.minX + tileRange.maxX) / 2;
    final centerTileY = (tileRange.minY + tileRange.maxY) / 2;
    final visibleTiles = <_TileVisualRequest>[
      for (var tileX = tileRange.minX; tileX <= tileRange.maxX; tileX += 1)
        for (var tileY = tileRange.minY; tileY <= tileRange.maxY; tileY += 1)
          _TileVisualRequest(
            x: tileX,
            y: tileY,
            priority: math.sqrt(
              math.pow(tileX - centerTileX, 2) +
                  math.pow(tileY - centerTileY, 2),
            ),
          ),
    ]..sort((left, right) => left.priority.compareTo(right.priority));

    return Stack(
      fit: StackFit.expand,
      children: [
        for (final tile in visibleTiles)
            Positioned(
              left: tile.x * tileWidth,
              top: tile.y * tileHeight,
              width: tileWidth,
              height: tileHeight,
              child: _TileImage(
                baseUrl: baseUrl,
                detailLevel: detailLevel,
                edgeSlug: edgeSlug,
                tileVersion: tileVersion,
                tileZoom: tileZoom,
                tileX: tile.x,
                tileY: tile.y,
                tileWidth: tileWidth,
                tileHeight: tileHeight,
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
    final radius = math.min(size.width, size.height) * 0.47;
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
    required this.detailLevel,
    required this.edgeSlug,
    required this.tileVersion,
    required this.tileZoom,
    required this.tileX,
    required this.tileY,
    required this.tileWidth,
    required this.tileHeight,
  });

  final String baseUrl;
  final String detailLevel;
  final String edgeSlug;
  final String tileVersion;
  final int tileZoom;
  final int tileX;
  final int tileY;
  final double tileWidth;
  final double tileHeight;

  @override
  Widget build(BuildContext context) {
    final tileUrl =
        '$baseUrl/map/tiles/$detailLevel/$edgeSlug/$tileZoom/$tileX/$tileY.png?v=$tileVersion';
    return Stack(
      fit: StackFit.expand,
      children: [
        if (tileZoom > 0)
          _ParentTileFallback(
            baseUrl: baseUrl,
            detailLevel: detailLevel,
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
    required this.detailLevel,
    required this.edgeSlug,
    required this.tileVersion,
    required this.tileZoom,
    required this.tileX,
    required this.tileY,
    required this.tileWidth,
    required this.tileHeight,
  });

  final String baseUrl;
  final String detailLevel;
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
        '$baseUrl/map/tiles/$detailLevel/$edgeSlug/$parentZoom/$parentX/$parentY.png?v=$tileVersion';

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
        _paintCoastStroke(canvas, entry.path, entry.shape, useFastCoastRendering);
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
      ..strokeCap = shape.name == 'Antarctica Rim'
          ? StrokeCap.round
          : StrokeCap.butt
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
    Listenable? repaint,
    required this.projectedScene,
    required this.markerAnchorPoints,
    required this.labelAnchorPoints,
    required this.markers,
    required this.labels,
    required this.showGrid,
    required this.gridStepDegrees,
    required this.edgeRenderMode,
    required this.showLabels,
    required this.showShapeLabels,
    required this.showStateBoundaries,
    required this.astronomySnapshot,
    required this.showSunPath,
    required this.showMoonPath,
    required this.astronomyObserverName,
    required this.routePoints,
    required this.labelScale,
    required this.viewScale,
    required this.viewRotationRadians,
    required this.animationValue,
    required this.isInteracting,
  }) : super(repaint: repaint);

  final _ProjectedSceneCache projectedScene;
  final List<Offset> markerAnchorPoints;
  final List<Offset> labelAnchorPoints;
  final List<PlaceMarker> markers;
  final List<MapLabel> labels;
  final bool showGrid;
  final int gridStepDegrees;
  final EdgeRenderMode edgeRenderMode;
  final bool showLabels;
  final bool showShapeLabels;
  final bool showStateBoundaries;
  final AstronomySnapshot? astronomySnapshot;
  final bool showSunPath;
  final bool showMoonPath;
  final String? astronomyObserverName;
  final List<PlaceMarker?> routePoints;
  final double labelScale;
  final double viewScale;
  final double viewRotationRadians;
  final double animationValue;
  final bool isInteracting;

  @override
  void paint(Canvas canvas, Size size) {
    final center = projectedScene.center;
    final mapRadius = projectedScene.mapRadius;

    if (astronomySnapshot != null && (showSunPath || showMoonPath)) {
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

    if (showShapeLabels && !isInteracting) {
      _paintShapeLabels(canvas);
    }

    if (showStateBoundaries) {
      _paintStateBoundaries(canvas);
    }

    if (showLabels) {
      _paintLayerLabels(
        canvas,
        center,
        mapRadius,
        projectedScene.landClipPath,
        projectedScene.projectedLandRings,
      );
    }

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

    if (projectedScene.landEntries.isEmpty && projectedScene.boundaryEntries.isEmpty) {
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

  Path _buildShapePath(
    Offset center,
    double mapRadius,
    List<MapRing> rings,
  ) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final ring in rings) {
      final firstPoint = _project(
        center,
        mapRadius,
        ring.points.first.x,
        ring.points.first.y,
      );
      path.moveTo(firstPoint.dx, firstPoint.dy);

      for (final point in ring.points.skip(1)) {
        final projected = _project(center, mapRadius, point.x, point.y);
        path.lineTo(projected.dx, projected.dy);
      }

      if (ring.closed) {
        path.close();
      }
    }
    return path;
  }

  List<Offset> _projectRing(
    Offset center,
    double mapRadius,
    MapRing ring,
  ) {
    return ring.points
        .map((point) => _project(center, mapRadius, point.x, point.y))
        .toList(growable: false);
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

  Offset _insetPointInsideLand(
    Offset snappedPoint, {
    required Offset originalPoint,
    required Path landClipPath,
  }) {
    return _insetPointInsideLandForDisplay(
      snappedPoint,
      originalPoint: originalPoint,
      landClipPath: landClipPath,
      viewScale: viewScale,
    );
  }

  Offset _normalizeOffset(Offset offset) {
    return _normalizeOffsetForDisplay(offset);
  }

  Offset? _findNearestLandEdgePoint(
    Offset point,
    List<List<Offset>> projectedLandRings,
  ) {
    return _findNearestLandEdgePointForDisplay(point, projectedLandRings);
  }

  Offset _nearestPointOnSegment(Offset point, Offset start, Offset end) {
    return _nearestPointOnSegmentForDisplay(point, start, end);
  }

  void _paintCoastStroke(
    Canvas canvas,
    Path path,
    MapShape shape,
    bool useFastCoastRendering,
    double viewScale,
  ) {
    final strokeWidth = shape.name == 'Antarctica Rim'
        ? _screenStableRadius(
            useFastCoastRendering ? 2.6 : 3.4,
            viewScale,
            minRadius: 1.6,
          )
        : _screenStableRadius(
            useFastCoastRendering ? 0.55 : 0.75,
            viewScale,
            minRadius: 0.28,
          );
    final strokePaint = Paint()
      ..color = shape.strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = shape.name == 'Antarctica Rim'
          ? StrokeCap.round
          : StrokeCap.butt
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawPath(path, strokePaint);
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

      final labelOffset = Offset(
        entry.bounds.center.dx - (labelPainter.width / 2),
        entry.bounds.center.dy - (labelPainter.height / 2),
      );
      _paintUprightLabel(
        canvas: canvas,
        center: entry.bounds.center,
        labelPainter: labelPainter,
      );
    }
  }

  void _paintStateBoundaries(Canvas canvas) {
    if (projectedScene.stateBoundaryEntries.isEmpty) {
      return;
    }

    canvas.save();
    canvas.clipPath(projectedScene.landClipPath);
    for (final entry in projectedScene.stateBoundaryEntries) {
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

  void _paintAstronomyOverlay(
    Canvas canvas,
    Offset center,
    double mapRadius,
  ) {
    final snapshot = astronomySnapshot;
    if (snapshot == null) {
      return;
    }

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: mapRadius)));
    _paintAstronomyLightMesh(canvas, center, mapRadius, snapshot);
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
      final observerRadius = _screenStableRadius(3.2, viewScale, minRadius: 1.2);
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

    for (var latitude = 85; latitude >= -90; latitude -= 5) {
      final nextLatitude = math.max(-90, latitude - 5).toDouble();
      for (var longitude = -180; longitude < 180; longitude += 5) {
        final nextLongitude = math.min(180, longitude + 5).toDouble();
        final cellLatitude = latitude - 2.5;
        final cellLongitude = longitude + 2.5;
        final sunIncidence = _hemisphereIncidence(
          cellLatitude,
          cellLongitude,
          sunLatitude,
          sunLongitude,
        );
        final moonIncidence = _hemisphereIncidence(
          cellLatitude,
          cellLongitude,
          moonLatitude,
          moonLongitude,
        );
        double darkness = sunIncidence >= 0
            ? 0.2 * (1 - sunIncidence)
            : 0.34 + 0.34 * (-sunIncidence).clamp(0.0, 1.0).toDouble();
        darkness -=
            moonStrength * moonIncidence.clamp(0.0, 1.0).toDouble();
        darkness = darkness.clamp(0.02, 0.68).toDouble();

        final cellPath = Path()
          ..moveTo(
            _projectLatLon(center, mapRadius, latitude.toDouble(), longitude.toDouble()).dx,
            _projectLatLon(center, mapRadius, latitude.toDouble(), longitude.toDouble()).dy,
          )
          ..lineTo(
            _projectLatLon(center, mapRadius, latitude.toDouble(), nextLongitude).dx,
            _projectLatLon(center, mapRadius, latitude.toDouble(), nextLongitude).dy,
          )
          ..lineTo(
            _projectLatLon(center, mapRadius, nextLatitude, nextLongitude).dx,
            _projectLatLon(center, mapRadius, nextLatitude, nextLongitude).dy,
          )
          ..lineTo(
            _projectLatLon(center, mapRadius, nextLatitude, longitude.toDouble()).dx,
            _projectLatLon(center, mapRadius, nextLatitude, longitude.toDouble()).dy,
          )
          ..close();

        final shadePaint = Paint()
          ..color = Color.lerp(
                const Color(0x00000000),
                const Color(0xCC07162B),
                darkness,
              ) ??
              const Color(0x6607162B)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;
        canvas.drawPath(cellPath, shadePaint);
      }
    }
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
    PlaceMarker point,
    {
      required String label,
      required Color color,
      required Color glowColor,
      required double baseRadius,
    }
  ) {
    final projected = _project(center, mapRadius, point.x, point.y);
    final pulse = 0.78 + (0.22 * math.sin(animationValue * math.pi * 2));
    final glowPaint = Paint()..color = glowColor;
    final bodyPaint = Paint()..color = color;
    final glowRadius = _screenStableRadius(
      baseRadius * (1.8 + pulse),
      viewScale,
      minRadius: 3.0,
    );
    final bodyRadius = _screenStableRadius(baseRadius, viewScale, minRadius: 1.8);
    canvas.drawCircle(projected, glowRadius, glowPaint);
    canvas.drawCircle(projected, bodyRadius, bodyPaint);

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

  void _paintLayerLabels(
    Canvas canvas,
    Offset center,
    double radius,
    Path landClipPath,
    List<List<Offset>> projectedLandRings,
  ) {
    for (var labelIndex = 0; labelIndex < labels.length; labelIndex += 1) {
      final label = labels[labelIndex];
      if (isInteracting &&
          (label.layer == 'city_regional' || label.layer == 'city_local')) {
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
              maxSnapDistanceInScreen: _isCityLayer(label.layer) ? 44 : 26,
            );
      final isCityLabel = _isCityLayer(label.layer);
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
        _ => TextStyle(
            color: Color(0xFF173042),
            fontSize: labelFontSize,
            fontWeight: FontWeight.w700,
          ),
      };

      final maxWidth = label.layer == 'continent' ? 170.0 : 130.0;
      final textPainter = TextPainter(
        text: TextSpan(text: label.name, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);

      if (isCityLabel) {
        final cityDotRadius = _screenStableRadius(2.2, viewScale, minRadius: 0.95);
        final cityDotPaint = Paint()..color = const Color(0xFF173042);
        canvas.drawCircle(point, cityDotRadius, cityDotPaint);
        _paintAnchoredPointLabel(
          canvas: canvas,
          anchorPoint: point,
          labelPainter: textPainter,
          labelOffsetInScreen: const Offset(13, -13),
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

    final labelCenter = center + _screenOffsetToScene(const Offset(0, -16), viewScale);
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
    final labelCenter = anchorPoint + _screenOffsetToScene(labelOffsetInScreen, viewScale);
    final leaderPaint = Paint()
      ..color = leaderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _screenStableRadius(0.9, viewScale, minRadius: 0.5);

    canvas.drawLine(
      anchorPoint + _screenOffsetToScene(Offset(dotRadius, -dotRadius), viewScale),
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
        oldDelegate.markers != markers ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.gridStepDegrees != gridStepDegrees ||
        oldDelegate.edgeRenderMode != edgeRenderMode ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.showShapeLabels != showShapeLabels ||
        oldDelegate.showStateBoundaries != showStateBoundaries ||
        oldDelegate.astronomySnapshot != astronomySnapshot ||
        oldDelegate.showSunPath != showSunPath ||
        oldDelegate.showMoonPath != showMoonPath ||
        oldDelegate.astronomyObserverName != astronomyObserverName ||
        oldDelegate.routePoints != routePoints ||
        oldDelegate.labels != labels ||
        oldDelegate.labelScale != labelScale ||
        oldDelegate.viewScale != viewScale ||
        oldDelegate.viewRotationRadians != viewRotationRadians ||
        oldDelegate.isInteracting != isInteracting;
  }
}
