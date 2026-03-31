import 'dart:async';

import 'package:flutter/material.dart';

import '../models/astronomy_event.dart';
import '../models/astronomy_snapshot.dart';
import '../data/city_catalog.dart';
import '../models/map_label.dart';
import '../models/map_scene.dart';
import '../models/map_shape.dart';
import '../models/measure_result.dart';
import '../models/place_marker.dart';
import '../services/maybeflat_api.dart';
import '../widgets/flat_world_canvas.dart';

enum _BackendStatus { checking, connected, offline, degraded }
enum _DistanceUnitDisplay { both, kilometers, miles }
enum _OuterEdgeMode { coastline, country, both }
enum _AstronomyTimeMode { current, custom }
enum _AstronomyEventFilter { all, solar, lunar }

const int _minRouteStops = 2;
const int _maxRouteStops = 6;
const List<int> _gridStepOptions = [5, 10, 15, 20, 30, 45, 60];
const int _healthFailureThreshold = 3;
const double _stateBoundaryZoomThreshold = 3.6;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MaybeflatApi _api = MaybeflatApi();
  final Map<String, MapScene> _sceneCache = {};
  final Set<String> _pendingSceneDetails = <String>{};
  final TextEditingController _astronomyObserverController =
      TextEditingController();
  final ScrollController _astronomyEventScrollController = ScrollController();
  final List<TextEditingController> _routeControllers = List.generate(
    _maxRouteStops,
    (_) => TextEditingController(),
  );

  Timer? _healthTimer;
  Timer? _astronomyTimer;
  int _consecutiveHealthFailures = 0;
  bool _isSyncing = false;
  bool _isMapInteracting = false;
  bool _isMeasuring = false;
  bool _isLoadingAstronomy = false;
  bool _isLoadingAstronomyEvents = false;
  bool _showAstronomyEventPicker = false;
  double _mapViewScale = 1.0;
  bool _showGrid = true;
  bool _showLabels = true;
  bool _showShapeLabels = false;
  bool _showStateBoundaries = true;
  bool _showSunPath = true;
  bool _showMoonPath = true;
  _OuterEdgeMode _outerEdgeMode = _OuterEdgeMode.coastline;
  _AstronomyTimeMode _astronomyTimeMode = _AstronomyTimeMode.current;
  int _gridStepDegrees = 15;
  bool _isLoading = true;
  String? _error;
  String? _measureError;
  String? _astronomyError;
  String? _astronomyEventError;
  _BackendStatus _backendStatus = _BackendStatus.checking;
  _DistanceUnitDisplay _distanceUnitDisplay = _DistanceUnitDisplay.both;
  int _stopCount = 2;
  int? _pickStopIndex;
  String _detailLevel = 'desktop';
  String _shapeSource = 'prototype';
  bool _usingRealCoastlines = false;
  String _boundarySource = 'unavailable';
  bool _usingCountryBoundaries = false;
  String _stateBoundarySource = 'unavailable';
  bool _usingStateBoundaries = false;
  bool _stateBoundaryLayerLoaded = false;
  List<PlaceMarker> _markers = const [];
  List<MapShape> _shapes = const [];
  List<MapLabel> _labels = const [];
  AstronomySnapshot? _astronomySnapshot;
  List<AstronomyEvent> _astronomyEvents = const [];
  _AstronomyEventFilter _astronomyEventFilter = _AstronomyEventFilter.all;
  String _astronomyEclipseSubtype = 'all';
  String? _selectedAstronomyEventId;
  CityCatalogEntry? _astronomyObserver;
  DateTime _astronomyCustomTime = DateTime.now();
  List<PlaceMarker?> _routePoints = List<PlaceMarker?>.filled(
    _maxRouteStops,
    null,
  );
  List<String?> _routePointSources = List<String?>.filled(_maxRouteStops, null);
  List<MeasureResult> _routeLegs = const [];

  @override
  void initState() {
    super.initState();
    _loadScene();
    _loadAstronomyEvents();
    _healthTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _refreshBackendStatus(),
    );
    _syncAstronomyTimer();
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    _astronomyTimer?.cancel();
    _astronomyObserverController.dispose();
    _astronomyEventScrollController.dispose();
    for (final controller in _routeControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadScene({bool showLoader = true}) async {
    if (_isSyncing) {
      return;
    }

    _isSyncing = true;
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
        _backendStatus = _BackendStatus.checking;
      });
    }

    final requestedDetail = _sceneCache.isEmpty
        ? _interactiveSceneDetail()
        : _currentSceneDetail();
    final includeStateBoundaries = _shouldLoadStateBoundaries();
    final sceneCacheKey = _sceneCacheKey(
      requestedDetail,
      includeStateBoundaries: includeStateBoundaries,
    );
    try {
      final scene = _sceneCache[sceneCacheKey] ??
          await _api.loadScene(
            detail: requestedDetail,
            includeStateBoundaries: includeStateBoundaries,
          );
      _sceneCache[sceneCacheKey] = scene;
      if (!mounted) {
        return;
      }
      _consecutiveHealthFailures = 0;
      _applyScene(scene);
      _prefetchSceneDetail(_restSceneDetail());
      _prefetchSceneDetail(_interactiveSceneDetail());
    } catch (_) {
      if (!mounted) {
        return;
      }
      final isHealthy = await _api.checkHealth();
      if (!mounted) {
        return;
      }
      _consecutiveHealthFailures = isHealthy
          ? 0
          : (_consecutiveHealthFailures + 1).clamp(0, 9999).toInt();
      final keepExistingScene = _shapes.isNotEmpty;
      if (keepExistingScene) {
        setState(() {
          _backendStatus = _BackendStatus.degraded;
          _error = isHealthy
              ? 'Backend is busy. Keeping the last loaded map scene until the next refresh completes.'
              : 'Backend is temporarily unavailable. Keeping the last loaded map scene.';
        });
      } else {
        _sceneCache.clear();
        setState(() {
          _backendStatus = isHealthy
              ? _BackendStatus.degraded
              : _BackendStatus.offline;
          _error = isHealthy
              ? 'Backend responded, but the scene payload could not be loaded.'
              : 'Backend is offline. Start the FastAPI server to load live map data.';
          _detailLevel = requestedDetail;
          _shapeSource = 'unavailable';
          _usingRealCoastlines = false;
          _boundarySource = 'unavailable';
          _usingCountryBoundaries = false;
          _stateBoundarySource = 'unavailable';
          _usingStateBoundaries = false;
          _stateBoundaryLayerLoaded = false;
          _markers = const [];
          _shapes = const [];
          _labels = const [];
          _clearRoutePlanner(keepSearchText: true);
        });
      }
    } finally {
      _isSyncing = false;
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshBackendStatus() async {
    if (_isSyncing) {
      return;
    }

    final isHealthy = await _api.checkHealth();
    if (!mounted) {
      return;
    }

    if (!isHealthy) {
      _consecutiveHealthFailures += 1;
      if (_consecutiveHealthFailures < _healthFailureThreshold) {
        if (_backendStatus == _BackendStatus.connected && mounted) {
          setState(() {
            _backendStatus = _BackendStatus.degraded;
            _error =
                'Backend is responding slowly under load. Keeping the current map scene.';
          });
        }
        return;
      }

      if (_shapes.isNotEmpty) {
        setState(() {
          _backendStatus = _BackendStatus.degraded;
          _error =
              'Backend is temporarily unavailable. Keeping the last loaded map scene.';
        });
        return;
      }

      if (_backendStatus != _BackendStatus.offline) {
        _sceneCache.clear();
        setState(() {
          _backendStatus = _BackendStatus.offline;
          _error =
              'Backend is offline. Start the FastAPI server to load live map data.';
          _detailLevel = _currentSceneDetail();
          _shapeSource = 'unavailable';
          _usingRealCoastlines = false;
          _boundarySource = 'unavailable';
          _usingCountryBoundaries = false;
          _stateBoundarySource = 'unavailable';
          _usingStateBoundaries = false;
          _stateBoundaryLayerLoaded = false;
          _markers = const [];
          _shapes = const [];
          _labels = const [];
          _clearRoutePlanner(keepSearchText: true);
        });
      }
      return;
    }

    _consecutiveHealthFailures = 0;
    final needsSceneReload = _backendStatus != _BackendStatus.connected ||
        _markers.isEmpty ||
        _shapes.isEmpty;
    if (needsSceneReload) {
      await _loadScene(showLoader: false);
      return;
    }

    if (_backendStatus != _BackendStatus.connected) {
      setState(() {
        _backendStatus = _BackendStatus.connected;
        _error = null;
      });
    }
  }

  String _currentSceneDetail() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final logicalWidth = view.physicalSize.width / view.devicePixelRatio;
    if (_isMapInteracting) {
      if (logicalWidth >= 1500) {
        return 'desktop';
      }
      return 'mobile';
    }

    if (logicalWidth >= 1500) {
      return 'full';
    }
    if (logicalWidth >= 900) {
      return 'desktop';
    }
    return 'mobile';
  }

  String _restSceneDetail() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final logicalWidth = view.physicalSize.width / view.devicePixelRatio;
    if (logicalWidth >= 1500) {
      return 'full';
    }
    if (logicalWidth >= 900) {
      return 'desktop';
    }
    return 'mobile';
  }

  String _interactiveSceneDetail() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final logicalWidth = view.physicalSize.width / view.devicePixelRatio;
    if (logicalWidth >= 1500) {
      return 'desktop';
    }
    return 'mobile';
  }

  void _applyScene(MapScene scene) {
    if (!mounted) {
      return;
    }

    setState(() {
      _backendStatus = _BackendStatus.connected;
      _error = null;
      _detailLevel = scene.detailLevel;
      _shapeSource = scene.shapeSource;
      _usingRealCoastlines = scene.usingRealCoastlines;
      _boundarySource = scene.boundarySource;
      _usingCountryBoundaries = scene.usingCountryBoundaries;
      _stateBoundarySource = scene.stateBoundarySource;
      _usingStateBoundaries = scene.usingStateBoundaries;
      _stateBoundaryLayerLoaded = scene.shapes.any(
        (shape) => shape.role == 'state_boundary',
      );
      _markers = scene.markers;
      _shapes = scene.shapes;
      _labels = scene.labels;
    });
    if (_shouldShowAstronomy && !_isLoadingAstronomy) {
      _loadAstronomy();
    }
    if (_astronomyEvents.isEmpty && !_isLoadingAstronomyEvents) {
      _loadAstronomyEvents();
    }
  }

  Future<void> _prefetchSceneDetail(String detail) async {
    final includeStateBoundaries = _shouldLoadStateBoundaries();
    final sceneCacheKey = _sceneCacheKey(
      detail,
      includeStateBoundaries: includeStateBoundaries,
    );
    if (_pendingSceneDetails.contains(sceneCacheKey) ||
        _sceneCache.containsKey(sceneCacheKey)) {
      return;
    }
    if (_backendStatus == _BackendStatus.offline) {
      return;
    }

    _pendingSceneDetails.add(sceneCacheKey);
    try {
      final scene = await _api.loadScene(
        detail: detail,
        includeStateBoundaries: includeStateBoundaries,
      );
      _sceneCache[sceneCacheKey] = scene;
      if (!mounted) {
        return;
      }
      final sceneHasStateBoundaryLayer = scene.shapes.any(
        (shape) => shape.role == 'state_boundary',
      );
      if (_currentSceneDetail() == detail &&
          (_detailLevel != detail ||
              _stateBoundaryLayerLoaded != sceneHasStateBoundaryLayer)) {
        _applyScene(scene);
      }
    } catch (_) {
      // Keep the current scene if a background prefetch fails.
    } finally {
      _pendingSceneDetails.remove(sceneCacheKey);
    }
  }

  void _handleMapInteractionChanged(bool isInteracting) {
    if (_isMapInteracting == isInteracting) {
      return;
    }

    _isMapInteracting = isInteracting;
    final targetDetail = _currentSceneDetail();
    final cachedScene = _sceneCache[_sceneCacheKey(
      targetDetail,
      includeStateBoundaries: _shouldLoadStateBoundaries(),
    )];
    final shouldApplyCachedScene = cachedScene != null &&
        (_detailLevel != targetDetail ||
            _stateBoundaryLayerLoaded !=
                cachedScene.shapes.any(
                  (shape) => shape.role == 'state_boundary',
                ));
    if (shouldApplyCachedScene) {
      _applyScene(cachedScene);
    } else {
      _prefetchSceneDetail(targetDetail);
    }

    if (isInteracting) {
      _prefetchSceneDetail(_restSceneDetail());
    } else {
      _prefetchSceneDetail(_interactiveSceneDetail());
    }
  }

  void _handleMapViewScaleChanged(double viewScale) {
    final previousShouldLoadStateBoundaries = _shouldLoadStateBoundaries();
    _mapViewScale = viewScale;
    final currentShouldLoadStateBoundaries = _shouldLoadStateBoundaries();
    if (previousShouldLoadStateBoundaries == currentShouldLoadStateBoundaries) {
      return;
    }

    final targetDetail = _currentSceneDetail();
    final cachedScene = _sceneCache[_sceneCacheKey(
      targetDetail,
      includeStateBoundaries: currentShouldLoadStateBoundaries,
    )];
    if (cachedScene != null) {
      _applyScene(cachedScene);
      return;
    }

    _prefetchSceneDetail(targetDetail);
  }

  bool _shouldLoadStateBoundaries() {
    return _showStateBoundaries && _mapViewScale >= _stateBoundaryZoomThreshold;
  }

  String _sceneCacheKey(
    String detail, {
    required bool includeStateBoundaries,
  }) {
    return '$detail|state:${includeStateBoundaries ? 1 : 0}';
  }

  bool get _shouldShowAstronomy => _showSunPath || _showMoonPath;

  DateTime _astronomyTimestampUtc() {
    return switch (_astronomyTimeMode) {
      _AstronomyTimeMode.current => DateTime.now().toUtc(),
      _AstronomyTimeMode.custom => _astronomyCustomTime.toUtc(),
    };
  }

  void _syncAstronomyTimer() {
    _astronomyTimer?.cancel();
    if (!_shouldShowAstronomy || _astronomyTimeMode != _AstronomyTimeMode.current) {
      return;
    }
    _astronomyTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _loadAstronomy(),
    );
  }

  Future<void> _loadAstronomyEvents() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoadingAstronomyEvents = true;
      _astronomyEventError = null;
    });

    try {
      final events = await _api.loadAstronomyEvents(
        eventType: 'eclipse',
        fromTimestampUtc: DateTime.now().toUtc(),
        limit: 24,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _astronomyEvents = events;
        if (!_availableAstronomyEclipseSubtypes.contains(_astronomyEclipseSubtype)) {
          _astronomyEclipseSubtype = 'all';
        }
        if (_selectedAstronomyEventId == null && events.isNotEmpty) {
          final filtered = _filteredAstronomyEvents;
          _selectedAstronomyEventId = filtered.isEmpty ? null : filtered.first.id;
        } else if (_selectedAstronomyEventId != null &&
            _filteredAstronomyEvents.every(
              (event) => event.id != _selectedAstronomyEventId,
            )) {
          final filtered = _filteredAstronomyEvents;
          _selectedAstronomyEventId = filtered.isEmpty ? null : filtered.first.id;
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _astronomyEventError =
            'Could not load the upcoming astronomy events from the backend.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAstronomyEvents = false;
        });
      }
    }
  }

  Future<void> _loadAstronomy() async {
    if (!_shouldShowAstronomy) {
      if (!mounted) {
        return;
      }
      setState(() {
        _astronomySnapshot = null;
        _astronomyError = null;
        _isLoadingAstronomy = false;
      });
      return;
    }
    if (_backendStatus == _BackendStatus.offline) {
      if (!mounted) {
        return;
      }
      setState(() {
        _astronomyError = 'Backend must be online to load the sun and moon overlay.';
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingAstronomy = true;
        _astronomyError = null;
      });
    }

    try {
      final observer = _astronomyObserver;
      final snapshot = await _api.loadAstronomySnapshot(
        timestampUtc: _astronomyTimestampUtc(),
        observerName: observer?.name,
        observerLatitude: observer?.latitude,
        observerLongitude: observer?.longitude,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _astronomySnapshot = snapshot;
        _astronomyError = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _astronomyError =
            'Could not load the live astronomy overlay from the backend.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAstronomy = false;
        });
      }
    }
  }

  void _setAstronomyToggle({
    bool? showSunPath,
    bool? showMoonPath,
  }) {
    setState(() {
      if (showSunPath != null) {
        _showSunPath = showSunPath;
      }
      if (showMoonPath != null) {
        _showMoonPath = showMoonPath;
      }
      if (!_shouldShowAstronomy) {
        _astronomySnapshot = null;
        _astronomyError = null;
      }
    });
    _syncAstronomyTimer();
    if (_shouldShowAstronomy) {
      _loadAstronomy();
    }
  }

  void _setAstronomyTimeMode(_AstronomyTimeMode mode) {
    setState(() {
      _astronomyTimeMode = mode;
    });
    _syncAstronomyTimer();
    if (_shouldShowAstronomy) {
      _loadAstronomy();
    }
  }

  Future<void> _pickAstronomyDateTime(BuildContext context) async {
    final initialDate = _astronomyCustomTime;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null || !mounted) {
      return;
    }

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_astronomyCustomTime),
    );
    if (pickedTime == null || !mounted) {
      return;
    }

    setState(() {
      _astronomyCustomTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });

    if (_shouldShowAstronomy) {
      _loadAstronomy();
    }
  }

  void _setAstronomyObserver(CityCatalogEntry? observer) {
    setState(() {
      _astronomyObserver = observer;
      _astronomyObserverController.text = observer?.name ?? '';
    });
    if (_shouldShowAstronomy) {
      _loadAstronomy();
    }
  }

  String _formatAstronomyTimeLabel(DateTime timestampUtc) {
    final local = timestampUtc.toLocal();
    final hour = local.hour == 0
        ? 12
        : (local.hour > 12 ? local.hour - 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final meridiem = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.month}/${local.day}/${local.year} $hour:$minute $meridiem';
  }

  List<AstronomyEvent> get _eventFilterMatchedAstronomyEvents {
    return switch (_astronomyEventFilter) {
      _AstronomyEventFilter.all => _astronomyEvents,
      _AstronomyEventFilter.solar =>
        _astronomyEvents.where((event) => event.isSolar).toList(growable: false),
      _AstronomyEventFilter.lunar =>
        _astronomyEvents.where((event) => event.isLunar).toList(growable: false),
    };
  }

  List<String> get _availableAstronomyEclipseSubtypes {
    final subtypes = _eventFilterMatchedAstronomyEvents
        .map((event) => event.subtype)
        .toSet()
        .toList()
      ..sort();
    return ['all', ...subtypes];
  }

  List<AstronomyEvent> get _filteredAstronomyEvents {
    final baseEvents = _eventFilterMatchedAstronomyEvents;
    if (_astronomyEclipseSubtype == 'all') {
      return baseEvents;
    }
    return baseEvents
        .where((event) => event.subtype == _astronomyEclipseSubtype)
        .toList(growable: false);
  }

  AstronomyEvent? get _selectedAstronomyEvent {
    final filtered = _filteredAstronomyEvents;
    if (filtered.isEmpty) {
      return null;
    }
    return filtered.firstWhere(
      (event) => event.id == _selectedAstronomyEventId,
      orElse: () => filtered.first,
    );
  }

  void _setAstronomyEventFilter(_AstronomyEventFilter? filter) {
    if (filter == null) {
      return;
    }
    setState(() {
      _astronomyEventFilter = filter;
      final availableSubtypes = _availableAstronomyEclipseSubtypes;
      if (!availableSubtypes.contains(_astronomyEclipseSubtype)) {
        _astronomyEclipseSubtype = 'all';
      }
      final filtered = _filteredAstronomyEvents;
      _selectedAstronomyEventId = filtered.isEmpty ? null : filtered.first.id;
      _showAstronomyEventPicker = false;
    });
  }

  void _setAstronomyEclipseSubtype(String? subtype) {
    if (subtype == null) {
      return;
    }
    setState(() {
      _astronomyEclipseSubtype = subtype;
      final filtered = _filteredAstronomyEvents;
      _selectedAstronomyEventId = filtered.isEmpty ? null : filtered.first.id;
      _showAstronomyEventPicker = false;
    });
  }

  void _toggleAstronomyEventPicker() {
    setState(() {
      _showAstronomyEventPicker = !_showAstronomyEventPicker;
    });
  }

  Future<void> _jumpToAstronomyEvent(AstronomyEvent? event) async {
    if (event == null) {
      return;
    }
    setState(() {
      _astronomyTimeMode = _AstronomyTimeMode.custom;
      _astronomyCustomTime = event.timestampUtc.toLocal();
      _selectedAstronomyEventId = event.id;
      _showSunPath = true;
      _showMoonPath = true;
      _showAstronomyEventPicker = false;
    });
    _syncAstronomyTimer();
    await _loadAstronomy();
  }

  Future<void> _stepAstronomyEvent(int delta) async {
    final filtered = _filteredAstronomyEvents;
    if (filtered.isEmpty) {
      return;
    }
    final current = _selectedAstronomyEvent;
    final currentIndex = current == null
        ? 0
        : filtered.indexWhere((event) => event.id == current.id);
    final nextIndex = (currentIndex < 0 ? 0 : currentIndex + delta)
        .clamp(0, filtered.length - 1);
    final nextEvent = filtered[nextIndex];
    await _jumpToAstronomyEvent(nextEvent);
  }

  Future<void> _setRouteStopFromCatalog(
    CityCatalogEntry entry,
    int stopIndex,
  ) async {
    if (_backendStatus != _BackendStatus.connected) {
      setState(() {
        _measureError = 'Backend must be connected to measure routes.';
      });
      return;
    }

    setState(() {
      _isMeasuring = true;
      _measureError = null;
      _routeLegs = const [];
    });

    try {
      final marker = await _api.transformPoint(
        name: entry.name,
        latitude: entry.latitude,
        longitude: entry.longitude,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _routePoints[stopIndex] = marker;
        _routePointSources[stopIndex] = entry.name;
        _routeControllers[stopIndex].text = entry.name;
      });

      await _refreshRouteMeasurement();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _measureError = 'Could not transform that city through the backend.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isMeasuring = false;
        });
      }
    }
  }

  Future<void> _setRouteStopFromMap(MapTapLocation selection) async {
    final stopIndex = _pickStopIndex;
    if (stopIndex == null) {
      return;
    }
    if (_backendStatus != _BackendStatus.connected) {
      setState(() {
        _measureError = 'Backend must be connected to measure routes.';
        _pickStopIndex = null;
      });
      return;
    }

    setState(() {
      _isMeasuring = true;
      _measureError = null;
      _routeLegs = const [];
    });

    try {
      final marker = await _api.transformPoint(
        name: 'Picked stop ${stopIndex + 1}',
        latitude: selection.latitude,
        longitude: selection.longitude,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _routePoints[stopIndex] = marker;
        _routePointSources[stopIndex] = _formatCoordinateSummary(
          selection.latitude,
          selection.longitude,
        );
        _routeControllers[stopIndex].text = 'Picked stop ${stopIndex + 1}';
        _pickStopIndex = null;
      });

      await _refreshRouteMeasurement();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _pickStopIndex = null;
        _measureError = 'Could not transform that picked map point.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isMeasuring = false;
        });
      }
    }
  }

  Future<void> _refreshRouteMeasurement() async {
    final activeStops = _routePoints.take(_stopCount).toList();
    if (activeStops.any((point) => point == null)) {
      if (!mounted) {
        return;
      }
      setState(() {
        _routeLegs = const [];
        _measureError = null;
      });
      return;
    }

    final filledStops = activeStops.whereType<PlaceMarker>().toList();
    if (filledStops.length < 2) {
      return;
    }

    try {
      final legFutures = <Future<MeasureResult>>[
        for (var index = 0; index < filledStops.length - 1; index += 1)
          _api.measurePoints(
            startLatitude: filledStops[index].latitude,
            startLongitude: filledStops[index].longitude,
            endLatitude: filledStops[index + 1].latitude,
            endLongitude: filledStops[index + 1].longitude,
          ),
      ];
      final results = await Future.wait(legFutures);
      if (!mounted) {
        return;
      }

      final updatedRoutePoints = List<PlaceMarker?>.from(_routePoints);
      updatedRoutePoints[0] = results.first.start;
      for (var index = 0; index < results.length; index += 1) {
        updatedRoutePoints[index + 1] = results[index].end;
      }

      setState(() {
        _routeLegs = results;
        _routePoints = updatedRoutePoints;
        _measureError = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _measureError = 'Could not measure that route through the backend.';
      });
    }
  }

  void _setPickStop(int stopIndex) {
    setState(() {
      _measureError = null;
      _pickStopIndex = _pickStopIndex == stopIndex ? null : stopIndex;
    });
  }

  void _setStopCount(int stopCount) {
    setState(() {
      _stopCount = stopCount;
      _routeLegs = const [];
      if (_pickStopIndex != null && _pickStopIndex! >= stopCount) {
        _pickStopIndex = null;
      }
      for (var index = stopCount; index < _maxRouteStops; index += 1) {
        _routePoints[index] = null;
        _routePointSources[index] = null;
        _routeControllers[index].clear();
      }
    });
    _refreshRouteMeasurement();
  }

  void _clearRoutePlanner({bool keepSearchText = false}) {
    _pickStopIndex = null;
    _measureError = null;
    _routeLegs = const [];
    for (var index = 0; index < _maxRouteStops; index += 1) {
      _routePoints[index] = null;
      _routePointSources[index] = null;
      if (!keepSearchText) {
        _routeControllers[index].clear();
      }
    }
  }

  String _formatCoordinateSummary(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(2)}, ${longitude.toStringAsFixed(2)}';
  }

  List<PlaceMarker?> get _activeRoutePoints => _routePoints.take(_stopCount).toList();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 980;

        final intro = _IntroPanel(
          showGrid: _showGrid,
          gridStepDegrees: _gridStepDegrees,
          outerEdgeMode: _outerEdgeMode,
          showLabels: _showLabels,
          showShapeLabels: _showShapeLabels,
          showStateBoundaries: _showStateBoundaries,
          showSunPath: _showSunPath,
          showMoonPath: _showMoonPath,
          astronomyTimeMode: _astronomyTimeMode,
          isLoading: _isLoading,
          isLoadingAstronomy: _isLoadingAstronomy,
          isMeasuring: _isMeasuring,
          error: _error,
          measureError: _measureError,
          astronomyError: _astronomyError,
          backendStatus: _backendStatus,
          detailLevel: _detailLevel,
          shapeSource: _shapeSource,
          usingRealCoastlines: _usingRealCoastlines,
          boundarySource: _boundarySource,
          usingCountryBoundaries: _usingCountryBoundaries,
          stateBoundarySource: _stateBoundarySource,
          usingStateBoundaries: _usingStateBoundaries,
          astronomySnapshot: _astronomySnapshot,
          astronomyEvents: _filteredAstronomyEvents,
          selectedAstronomyEvent: _selectedAstronomyEvent,
          astronomyEventFilter: _astronomyEventFilter,
          astronomyEclipseSubtype: _astronomyEclipseSubtype,
          astronomyEclipseSubtypeOptions: _availableAstronomyEclipseSubtypes,
          showAstronomyEventPicker: _showAstronomyEventPicker,
          astronomyObserverController: _astronomyObserverController,
          astronomyEventScrollController: _astronomyEventScrollController,
          astronomyObserverName: _astronomyObserver?.name,
          astronomyCustomTimeLabel: _formatAstronomyTimeLabel(
            _astronomyCustomTime.toUtc(),
          ),
          isLoadingAstronomyEvents: _isLoadingAstronomyEvents,
          astronomyEventError: _astronomyEventError,
          markerCount: _markers.length,
          shapeCount: _shapes.length,
          stopCount: _stopCount,
          stopControllers: _routeControllers,
          stopSources: _routePointSources,
          routeLegs: _routeLegs,
          distanceUnitDisplay: _distanceUnitDisplay,
          activePickStopIndex: _pickStopIndex,
          onShowGridChanged: (value) => setState(() => _showGrid = value),
          onGridStepChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() {
              _gridStepDegrees = value;
            });
          },
          onShowLabelsChanged: (value) => setState(() => _showLabels = value),
          onOuterEdgeModeChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() {
              _outerEdgeMode = value;
            });
          },
          onShowShapeLabelsChanged: (value) =>
              setState(() => _showShapeLabels = value),
          onShowStateBoundariesChanged: (value) {
            setState(() {
              _showStateBoundaries = value;
            });
            _handleMapViewScaleChanged(_mapViewScale);
          },
          onShowSunPathChanged: (value) => _setAstronomyToggle(showSunPath: value),
          onShowMoonPathChanged: (value) =>
              _setAstronomyToggle(showMoonPath: value),
          onAstronomyTimeModeChanged: (value) {
            if (value == null) {
              return;
            }
            _setAstronomyTimeMode(value);
          },
          onAstronomyDateTimePressed: () => _pickAstronomyDateTime(context),
          onAstronomyObserverSelected: _setAstronomyObserver,
          onClearAstronomyObserver: () => _setAstronomyObserver(null),
          onAstronomyEventFilterChanged: _setAstronomyEventFilter,
          onAstronomyEclipseSubtypeChanged: _setAstronomyEclipseSubtype,
          onAstronomyEventSelected: (event) {
            if (event != null) {
              _jumpToAstronomyEvent(event);
            }
          },
          onToggleAstronomyEventPicker: _toggleAstronomyEventPicker,
          onPreviousAstronomyEvent: () => _stepAstronomyEvent(-1),
          onNextAstronomyEvent: () => _stepAstronomyEvent(1),
          onReload: () async {
            _sceneCache.clear();
            await _loadScene(showLoader: true);
          },
          onDistanceUnitDisplayChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() {
              _distanceUnitDisplay = value;
            });
          },
          onStopCountChanged: (value) {
            if (value == null) {
              return;
            }
            _setStopCount(value);
          },
          onStopCitySelected: _setRouteStopFromCatalog,
          onPickStop: _setPickStop,
          onClearRoute: () => setState(() {
            _clearRoutePlanner();
          }),
        );

        final mapCard = Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'North-centered flat map prototype',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF112A46),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Version 0 renders a circular plane, uses a custom latitude-to-radius transform, and reserves the outer ring for Antarctica.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: Color(0xFF335C67),
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: Center(
                    child: FlatWorldCanvas(
                      tileBaseUrl: _api.baseUrl,
                      tileDetailLevel: _detailLevel,
                      markers: _markers,
                      shapes: _shapes,
                      labels: _labels,
                      showGrid: _showGrid,
                      gridStepDegrees: _gridStepDegrees,
                      edgeRenderMode: switch (_outerEdgeMode) {
                        _OuterEdgeMode.coastline => EdgeRenderMode.coastline,
                        _OuterEdgeMode.country => EdgeRenderMode.country,
                        _OuterEdgeMode.both => EdgeRenderMode.both,
                      },
                      showLabels: _showLabels,
                      showShapeLabels: _showShapeLabels,
                      showStateBoundaries:
                          _showStateBoundaries &&
                          _mapViewScale >= _stateBoundaryZoomThreshold,
                      astronomySnapshot: _astronomySnapshot,
                      showSunPath: _showSunPath,
                      showMoonPath: _showMoonPath,
                      astronomyObserverName: _astronomyObserver?.name,
                      routePoints: _activeRoutePoints,
                      activePickLabel: _pickStopIndex == null
                          ? null
                          : '${_pickStopIndex! + 1}',
                      onMapPointPicked: _setRouteStopFromMap,
                      onInteractionChanged: _handleMapInteractionChanged,
                      onViewScaleChanged: _handleMapViewScaleChanged,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 380, child: intro),
                        const SizedBox(width: 20),
                        Expanded(child: mapCard),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        intro,
                        const SizedBox(height: 20),
                        Expanded(child: mapCard),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _IntroPanel extends StatelessWidget {
  const _IntroPanel({
    required this.showGrid,
    required this.gridStepDegrees,
    required this.outerEdgeMode,
    required this.showLabels,
    required this.showShapeLabels,
    required this.showStateBoundaries,
    required this.showSunPath,
    required this.showMoonPath,
    required this.astronomyTimeMode,
    required this.isLoading,
    required this.isLoadingAstronomy,
    required this.isMeasuring,
    required this.error,
    required this.measureError,
    required this.astronomyError,
    required this.backendStatus,
    required this.detailLevel,
    required this.shapeSource,
    required this.usingRealCoastlines,
    required this.boundarySource,
    required this.usingCountryBoundaries,
    required this.stateBoundarySource,
    required this.usingStateBoundaries,
    required this.astronomySnapshot,
    required this.astronomyEvents,
    required this.selectedAstronomyEvent,
    required this.astronomyEventFilter,
    required this.astronomyEclipseSubtype,
    required this.astronomyEclipseSubtypeOptions,
    required this.showAstronomyEventPicker,
    required this.astronomyObserverController,
    required this.astronomyEventScrollController,
    required this.astronomyObserverName,
    required this.astronomyCustomTimeLabel,
    required this.isLoadingAstronomyEvents,
    required this.astronomyEventError,
    required this.markerCount,
    required this.shapeCount,
    required this.stopCount,
    required this.stopControllers,
    required this.stopSources,
    required this.routeLegs,
    required this.distanceUnitDisplay,
    required this.activePickStopIndex,
    required this.onShowGridChanged,
    required this.onGridStepChanged,
    required this.onOuterEdgeModeChanged,
    required this.onShowLabelsChanged,
    required this.onShowShapeLabelsChanged,
    required this.onShowStateBoundariesChanged,
    required this.onShowSunPathChanged,
    required this.onShowMoonPathChanged,
    required this.onAstronomyTimeModeChanged,
    required this.onAstronomyDateTimePressed,
    required this.onAstronomyObserverSelected,
    required this.onClearAstronomyObserver,
    required this.onAstronomyEventFilterChanged,
    required this.onAstronomyEclipseSubtypeChanged,
    required this.onAstronomyEventSelected,
    required this.onToggleAstronomyEventPicker,
    required this.onPreviousAstronomyEvent,
    required this.onNextAstronomyEvent,
    required this.onReload,
    required this.onDistanceUnitDisplayChanged,
    required this.onStopCountChanged,
    required this.onStopCitySelected,
    required this.onPickStop,
    required this.onClearRoute,
  });

  final bool showGrid;
  final int gridStepDegrees;
  final _OuterEdgeMode outerEdgeMode;
  final bool showLabels;
  final bool showShapeLabels;
  final bool showStateBoundaries;
  final bool showSunPath;
  final bool showMoonPath;
  final _AstronomyTimeMode astronomyTimeMode;
  final bool isLoading;
  final bool isLoadingAstronomy;
  final bool isMeasuring;
  final String? error;
  final String? measureError;
  final String? astronomyError;
  final _BackendStatus backendStatus;
  final String detailLevel;
  final String shapeSource;
  final bool usingRealCoastlines;
  final String boundarySource;
  final bool usingCountryBoundaries;
  final String stateBoundarySource;
  final bool usingStateBoundaries;
  final AstronomySnapshot? astronomySnapshot;
  final List<AstronomyEvent> astronomyEvents;
  final AstronomyEvent? selectedAstronomyEvent;
  final _AstronomyEventFilter astronomyEventFilter;
  final String astronomyEclipseSubtype;
  final List<String> astronomyEclipseSubtypeOptions;
  final bool showAstronomyEventPicker;
  final TextEditingController astronomyObserverController;
  final ScrollController astronomyEventScrollController;
  final String? astronomyObserverName;
  final String astronomyCustomTimeLabel;
  final bool isLoadingAstronomyEvents;
  final String? astronomyEventError;
  final int markerCount;
  final int shapeCount;
  final int stopCount;
  final List<TextEditingController> stopControllers;
  final List<String?> stopSources;
  final List<MeasureResult> routeLegs;
  final _DistanceUnitDisplay distanceUnitDisplay;
  final int? activePickStopIndex;
  final ValueChanged<bool> onShowGridChanged;
  final ValueChanged<int?> onGridStepChanged;
  final ValueChanged<_OuterEdgeMode?> onOuterEdgeModeChanged;
  final ValueChanged<bool> onShowLabelsChanged;
  final ValueChanged<bool> onShowShapeLabelsChanged;
  final ValueChanged<bool> onShowStateBoundariesChanged;
  final ValueChanged<bool> onShowSunPathChanged;
  final ValueChanged<bool> onShowMoonPathChanged;
  final ValueChanged<_AstronomyTimeMode?> onAstronomyTimeModeChanged;
  final VoidCallback onAstronomyDateTimePressed;
  final ValueChanged<CityCatalogEntry?> onAstronomyObserverSelected;
  final VoidCallback onClearAstronomyObserver;
  final ValueChanged<_AstronomyEventFilter?> onAstronomyEventFilterChanged;
  final ValueChanged<String?> onAstronomyEclipseSubtypeChanged;
  final ValueChanged<AstronomyEvent?> onAstronomyEventSelected;
  final VoidCallback onToggleAstronomyEventPicker;
  final VoidCallback onPreviousAstronomyEvent;
  final VoidCallback onNextAstronomyEvent;
  final Future<void> Function() onReload;
  final ValueChanged<_DistanceUnitDisplay?> onDistanceUnitDisplayChanged;
  final ValueChanged<int?> onStopCountChanged;
  final void Function(CityCatalogEntry entry, int stopIndex) onStopCitySelected;
  final ValueChanged<int> onPickStop;
  final VoidCallback onClearRoute;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Maybeflat',
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF112A46),
                  height: 0.95,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Interactive flat-world exploration for desktop and phone.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Color(0xFF335C67),
                ),
              ),
              const SizedBox(height: 28),
              _StatusRow(status: backendStatus),
              const SizedBox(height: 18),
              const _InfoRow(
                title: 'Center',
                value: 'North Pole fixed at the origin',
              ),
              const _InfoRow(
                title: 'Outer Ring',
                value: 'Antarctica occupies the perimeter band',
              ),
              const _InfoRow(
                title: 'Distance',
                value: 'Measured on the flat plane',
              ),
              const SizedBox(height: 22),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: showGrid,
                title: const Text('Show lat/lon grid'),
                onChanged: onShowGridChanged,
              ),
              DropdownButtonFormField<int>(
                value: gridStepDegrees,
                decoration: const InputDecoration(
                  labelText: 'Grid interval',
                  helperText: 'Multiples of 5 degrees',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final step in _gridStepOptions)
                    DropdownMenuItem(
                      value: step,
                      child: Text('$step degrees'),
                    ),
                ],
                onChanged: showGrid ? onGridStepChanged : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<_OuterEdgeMode>(
                value: outerEdgeMode,
                decoration: const InputDecoration(
                  labelText: 'Outer edge source',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: _OuterEdgeMode.coastline,
                    child: Text('Coastline'),
                  ),
                  DropdownMenuItem(
                    value: _OuterEdgeMode.country,
                    child: Text('Country'),
                  ),
                  DropdownMenuItem(
                    value: _OuterEdgeMode.both,
                    child: Text('Both'),
                  ),
                ],
                onChanged: onOuterEdgeModeChanged,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: showLabels,
                title: const Text('Show city labels'),
                onChanged: onShowLabelsChanged,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: showShapeLabels,
                title: const Text('Show coast labels'),
                onChanged: onShowShapeLabelsChanged,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: showStateBoundaries,
                title: const Text('Show state/province boundaries'),
                onChanged: usingStateBoundaries
                    ? onShowStateBoundariesChanged
                    : null,
              ),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 18),
              const Text(
                'Astronomy Overlay',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF112A46),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Show the live sun and moon over the full map, including lit and dark regions from above.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Color(0xFF335C67),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: showSunPath,
                title: const Text('Sun path'),
                onChanged: onShowSunPathChanged,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: showMoonPath,
                title: const Text('Moon path'),
                onChanged: onShowMoonPathChanged,
              ),
              DropdownButtonFormField<_AstronomyTimeMode>(
                value: astronomyTimeMode,
                decoration: const InputDecoration(
                  labelText: 'Astronomy time',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: _AstronomyTimeMode.current,
                    child: Text('Current time'),
                  ),
                  DropdownMenuItem(
                    value: _AstronomyTimeMode.custom,
                    child: Text('Custom time'),
                  ),
                ],
                onChanged: onAstronomyTimeModeChanged,
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: astronomyTimeMode == _AstronomyTimeMode.custom
                    ? onAstronomyDateTimePressed
                    : null,
                child: Text(
                  astronomyTimeMode == _AstronomyTimeMode.current
                      ? 'Using current time'
                      : astronomyCustomTimeLabel,
                ),
              ),
              const SizedBox(height: 12),
              _CitySearchField(
                label: 'Observer city',
                controller: astronomyObserverController,
                onSelected: onAstronomyObserverSelected,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      astronomyObserverName == null
                          ? 'Observer: none selected'
                          : 'Observer: $astronomyObserverName',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF335C67),
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: astronomyObserverName == null
                        ? null
                        : onClearAstronomyObserver,
                    child: const Text('Clear'),
                  ),
                ],
              ),
              if (isLoadingAstronomy) ...[
                const SizedBox(height: 10),
                const Text(
                  'Loading live astronomy...',
                  style: TextStyle(
                    color: Color(0xFF335C67),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (astronomySnapshot != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7EFF5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Snapshot: ${_formatSnapshotTime(astronomySnapshot!)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF112A46),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Moon phase: ${astronomySnapshot!.moon.phaseName ?? 'Unavailable'}'
                        ' (${_formatIllumination(astronomySnapshot!.moon.illuminationFraction)})',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF335C67),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sun over: ${_formatBodySummary(astronomySnapshot!.sun.subpoint)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF335C67),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Moon over: ${_formatBodySummary(astronomySnapshot!.moon.subpoint)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF335C67),
                          height: 1.35,
                        ),
                      ),
                      if (astronomySnapshot!.observer != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _formatObserverSummary(astronomySnapshot!.observer!),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF112A46),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const Text(
                'Upcoming events',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF112A46),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Event filter',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF112A46),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<_AstronomyEventFilter>(
                value: astronomyEventFilter,
                decoration: InputDecoration(
                  labelText: 'Event Filter',
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFFBFCBD5)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFF112A46), width: 1.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: _AstronomyEventFilter.all,
                    child: Text('All eclipses'),
                  ),
                  DropdownMenuItem(
                    value: _AstronomyEventFilter.solar,
                    child: Text('Solar eclipses'),
                  ),
                  DropdownMenuItem(
                    value: _AstronomyEventFilter.lunar,
                    child: Text('Lunar eclipses'),
                  ),
                ],
                onChanged: onAstronomyEventFilterChanged,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: astronomyEclipseSubtype,
                decoration: InputDecoration(
                  labelText: 'Eclipse Type',
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFFBFCBD5)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(
                      color: Color(0xFF112A46),
                      width: 1.4,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  isDense: true,
                ),
                items: [
                  for (final subtype in astronomyEclipseSubtypeOptions)
                    DropdownMenuItem(
                      value: subtype,
                      child: Text(_formatEclipseSubtypeOption(subtype)),
                    ),
                ],
                onChanged: onAstronomyEclipseSubtypeChanged,
              ),
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: astronomyEvents.isEmpty ? null : onToggleAstronomyEventPicker,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFBFCBD5)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: astronomyEvents.isEmpty
                      ? const Text(
                          'No events available for this filter.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF335C67),
                            height: 1.35,
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: selectedAstronomyEvent == null
                                  ? const Text(
                                      'Select event',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF335C67),
                                        height: 1.35,
                                      ),
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          selectedAstronomyEvent!.title,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF112A46),
                                            height: 1.3,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatEventTime(
                                            selectedAstronomyEvent!,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF335C67),
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              showAstronomyEventPicker
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: const Color(0xFF335C67),
                            ),
                          ],
                        ),
                ),
              ),
              if (showAstronomyEventPicker && astronomyEvents.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFB6C7D1)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SizedBox(
                    height: 184,
                    child: Scrollbar(
                      controller: astronomyEventScrollController,
                      thumbVisibility: true,
                      child: ListView.separated(
                        controller: astronomyEventScrollController,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: astronomyEvents.length,
                        separatorBuilder: (context, index) => const Divider(
                          height: 1,
                          color: Color(0xFFD7E0E5),
                        ),
                        itemBuilder: (context, index) {
                          final event = astronomyEvents[index];
                          final isSelected =
                              selectedAstronomyEvent?.id == event.id;
                          return Material(
                            color: isSelected
                                ? const Color(0xFFE7EFF5)
                                : Colors.transparent,
                            child: InkWell(
                              onTap: () => onAstronomyEventSelected(event),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      event.title,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSelected
                                            ? FontWeight.w800
                                            : FontWeight.w700,
                                        color: const Color(0xFF112A46),
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatEventTime(event),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF335C67),
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF112A46),
                        foregroundColor: const Color(0xFFF8F3E8),
                      ),
                      onPressed: astronomyEvents.isEmpty
                          ? null
                          : onPreviousAstronomyEvent,
                      child: const Text(
                        'Previous',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF112A46),
                        foregroundColor: const Color(0xFFF8F3E8),
                      ),
                      onPressed:
                          astronomyEvents.isEmpty ? null : onNextAstronomyEvent,
                      child: const Text(
                        'Next',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              if (isLoadingAstronomyEvents) ...[
                const SizedBox(height: 10),
                const Text(
                  'Loading event calendar...',
                  style: TextStyle(
                    color: Color(0xFF335C67),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (selectedAstronomyEvent != null) ...[
                const SizedBox(height: 10),
                Text(
                  '${selectedAstronomyEvent!.title} - ${_formatEventSubtype(selectedAstronomyEvent!)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF112A46),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatEventTime(selectedAstronomyEvent!),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF335C67),
                    height: 1.35,
                  ),
                ),
                if (selectedAstronomyEvent!.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    selectedAstronomyEvent!.description!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF335C67),
                      height: 1.35,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: isLoading ? null : () => onReload(),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF112A46),
                  foregroundColor: const Color(0xFFF8F3E8),
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(
                  isLoading ? 'Loading backend scene...' : 'Reload backend scene',
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Backend markers loaded: $markerCount',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF112A46),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Vector layers loaded: $shapeCount',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF112A46),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                usingRealCoastlines
                    ? 'Coastline source: $shapeSource'
                    : 'Coastline source: prototype shapes',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF112A46),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                usingCountryBoundaries
                    ? 'Country boundaries: $boundarySource'
                    : 'Country boundaries: unavailable',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF112A46),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                usingStateBoundaries
                    ? 'State/province boundaries: $stateBoundarySource'
                    : 'State/province boundaries: unavailable',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF112A46),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Coastline detail: $detailLevel',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF112A46),
                ),
              ),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 18),
              const Text(
                'Route Planner',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF112A46),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Build an ordered route with cities or manual map picks. The route follows the stop order you choose.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Color(0xFF335C67),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<_DistanceUnitDisplay>(
                value: distanceUnitDisplay,
                decoration: const InputDecoration(
                  labelText: 'Distance units',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: _DistanceUnitDisplay.both,
                    child: Text('Both'),
                  ),
                  DropdownMenuItem(
                    value: _DistanceUnitDisplay.kilometers,
                    child: Text('Kilometers'),
                  ),
                  DropdownMenuItem(
                    value: _DistanceUnitDisplay.miles,
                    child: Text('Miles'),
                  ),
                ],
                onChanged: onDistanceUnitDisplayChanged,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: stopCount,
                decoration: const InputDecoration(
                  labelText: 'How many stops',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (var count = _minRouteStops;
                      count <= _maxRouteStops;
                      count += 1)
                    DropdownMenuItem(
                      value: count,
                      child: Text('$count stops'),
                    ),
                ],
                onChanged: onStopCountChanged,
              ),
              const SizedBox(height: 16),
              for (var index = 0; index < stopCount; index += 1) ...[
                _CitySearchField(
                  label: 'Stop ${index + 1} city',
                  controller: stopControllers[index],
                  onSelected: (entry) => onStopCitySelected(entry, index),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Selected: ${stopSources[index] ?? 'Not set'}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF335C67),
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () => onPickStop(index),
                      child: Text(
                        activePickStopIndex == index
                            ? 'Picking...'
                            : 'Pick on map',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton(
                onPressed: onClearRoute,
                child: const Text('Clear route'),
              ),
              if (isMeasuring) ...[
                const SizedBox(height: 10),
                const Text(
                  'Measuring route...',
                  style: TextStyle(
                    color: Color(0xFF335C67),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (_routeReady(stopSources, stopCount) && routeLegs.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6ECD2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _totalDistanceSummary(routeLegs, distanceUnitDisplay),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF112A46),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Leg breakdown',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF335C67),
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (var index = 0; index < routeLegs.length; index += 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '${index + 1}. ${stopSources[index] ?? 'Stop ${index + 1}'} -> ${stopSources[index + 1] ?? 'Stop ${index + 2}'}: ${_legDistanceSummary(routeLegs[index], distanceUnitDisplay)}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF335C67),
                              height: 1.35,
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        'Raw plane total: ${_rawPlaneTotal(routeLegs)} map units',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF5C6B73),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        routeLegs.first.distanceReferenceNote,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF5C6B73),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                Text(
                  'Set all $stopCount stops to measure the full route.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF335C67),
                    height: 1.35,
                  ),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(
                  error!,
                  style: const TextStyle(
                    color: Color(0xFF9B2226),
                    height: 1.4,
                  ),
                ),
              ],
              if (measureError != null) ...[
                const SizedBox(height: 10),
                Text(
                  measureError!,
                  style: const TextStyle(
                    color: Color(0xFF9B2226),
                    height: 1.4,
                  ),
                ),
              ],
              if (astronomyError != null) ...[
                const SizedBox(height: 10),
                Text(
                  astronomyError!,
                  style: const TextStyle(
                    color: Color(0xFF9B2226),
                    height: 1.4,
                  ),
                ),
              ],
              if (astronomyEventError != null) ...[
                const SizedBox(height: 10),
                Text(
                  astronomyEventError!,
                  style: const TextStyle(
                    color: Color(0xFF9B2226),
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const Text(
                'Scene data now comes from the backend. If the API is offline, the map should stay empty instead of silently faking local results.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: Color(0xFF335C67),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _routeReady(List<String?> stopSources, int stopCount) {
    return stopSources.take(stopCount).every((source) => source != null);
  }

  String _totalDistanceSummary(
    List<MeasureResult> routeLegs,
    _DistanceUnitDisplay unitDisplay,
  ) {
    final totalKm = routeLegs.fold<double>(
      0,
      (sum, leg) => sum + leg.geodesicDistanceKm,
    );
    final totalMiles = routeLegs.fold<double>(
      0,
      (sum, leg) => sum + leg.geodesicDistanceMiles,
    );

    return switch (unitDisplay) {
      _DistanceUnitDisplay.kilometers =>
        'Geodesic route total: ${totalKm.toStringAsFixed(1)} km',
      _DistanceUnitDisplay.miles =>
        'Geodesic route total: ${totalMiles.toStringAsFixed(1)} miles',
      _DistanceUnitDisplay.both =>
        'Geodesic route total: ${totalKm.toStringAsFixed(1)} km / ${totalMiles.toStringAsFixed(1)} miles',
    };
  }

  String _legDistanceSummary(
    MeasureResult routeLeg,
    _DistanceUnitDisplay unitDisplay,
  ) {
    return switch (unitDisplay) {
      _DistanceUnitDisplay.kilometers =>
        '${routeLeg.geodesicDistanceKm.toStringAsFixed(1)} km',
      _DistanceUnitDisplay.miles =>
        '${routeLeg.geodesicDistanceMiles.toStringAsFixed(1)} miles',
      _DistanceUnitDisplay.both =>
        '${routeLeg.geodesicDistanceKm.toStringAsFixed(1)} km / ${routeLeg.geodesicDistanceMiles.toStringAsFixed(1)} miles',
    };
  }

  String _rawPlaneTotal(List<MeasureResult> routeLegs) {
    final total = routeLegs.fold<double>(
      0,
      (sum, leg) => sum + leg.planeDistance,
    );
    return total.toStringAsFixed(3);
  }

  String _formatSnapshotTime(AstronomySnapshot snapshot) {
    final local = snapshot.timestampUtc.toLocal();
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day}/${local.year} ${local.hour.toString().padLeft(2, '0')}:$minute';
  }

  String _formatIllumination(double? fraction) {
    final percent = ((fraction ?? 0) * 100).toStringAsFixed(1);
    return '$percent% illuminated';
  }

  String _formatBodySummary(PlaceMarker marker) {
    return '${marker.latitude.toStringAsFixed(1)} deg, ${marker.longitude.toStringAsFixed(1)} deg';
  }

  String _formatObserverSummary(AstronomyObserver observer) {
    final daylightLabel = observer.isDaylight ? 'daylight' : 'night';
    final moonLabel = observer.isMoonVisible ? 'Moon above horizon' : 'Moon below horizon';
    return '${observer.name ?? 'Observer'}: $daylightLabel, sun ${observer.sunAltitudeDegrees.toStringAsFixed(1)} deg, moon ${observer.moonAltitudeDegrees.toStringAsFixed(1)} deg, $moonLabel.';
  }

  String _formatEventSubtype(AstronomyEvent event) {
    return switch (event.subtype) {
      'solar_total' => 'Solar total',
      'solar_annular' => 'Solar annular',
      'solar_partial' => 'Solar partial',
      'lunar_total' => 'Lunar total',
      'lunar_partial' => 'Lunar partial',
      'lunar_penumbral' => 'Lunar penumbral',
      _ => event.subtype.replaceAll('_', ' '),
    };
  }

  String _formatEclipseSubtypeOption(String subtype) {
    return switch (subtype) {
      'all' => 'All types',
      'solar_total' => 'Solar total',
      'solar_annular' => 'Solar annular',
      'solar_partial' => 'Solar partial',
      'lunar_total' => 'Lunar total',
      'lunar_partial' => 'Lunar partial',
      'lunar_penumbral' => 'Lunar penumbral',
      _ => subtype.replaceAll('_', ' '),
    };
  }

  String _formatEventTime(AstronomyEvent event) {
    final local = event.timestampUtc.toLocal();
    final minute = local.minute.toString().padLeft(2, '0');
    final meridiem = local.hour >= 12 ? 'PM' : 'AM';
    final hour = local.hour == 0
        ? 12
        : (local.hour > 12 ? local.hour - 12 : local.hour);
    return '${local.month}/${local.day}/${local.year} $hour:$minute $meridiem';
  }
}

class _CitySearchField extends StatelessWidget {
  const _CitySearchField({
    required this.label,
    required this.controller,
    required this.onSelected,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<CityCatalogEntry> onSelected;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<CityCatalogEntry>(
      key: ValueKey('$label:${controller.text}'),
      initialValue: TextEditingValue(text: controller.text),
      displayStringForOption: (option) => option.name,
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) {
          return cityCatalog.take(8);
        }

        return cityCatalog
            .where((entry) => entry.name.toLowerCase().contains(query))
            .take(8);
      },
      onSelected: onSelected,
      fieldViewBuilder:
          (context, textEditingController, focusNode, onSubmitted) {
        return TextField(
          controller: textEditingController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            hintText: 'Type a city name',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        );
      },
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.status,
  });

  final _BackendStatus status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      _BackendStatus.checking => 'Checking backend',
      _BackendStatus.connected => 'Connected live',
      _BackendStatus.offline => 'Offline',
      _BackendStatus.degraded => 'Connected with errors',
    };

    final backgroundColor = switch (status) {
      _BackendStatus.checking => const Color(0xFFE8EDF3),
      _BackendStatus.connected => const Color(0xFFD8F0DF),
      _BackendStatus.offline => const Color(0xFFF4D8D9),
      _BackendStatus.degraded => const Color(0xFFF5E6C8),
    };

    final dotColor = switch (status) {
      _BackendStatus.checking => const Color(0xFF5C6B73),
      _BackendStatus.connected => const Color(0xFF2D6A4F),
      _BackendStatus.offline => const Color(0xFF9B2226),
      _BackendStatus.degraded => const Color(0xFF9C6644),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF112A46),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF112A46),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF335C67),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
