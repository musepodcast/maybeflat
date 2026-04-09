import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/astronomy_event.dart';
import '../models/astronomy_snapshot.dart';
import '../models/city_search_result.dart';
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

enum _AstronomyPlaybackPreset {
  oneDay,
  sevenDays,
  twentyEightDays,
  threeSixtyFiveDays,
  fiveYears,
  tenYears,
  custom,
}

enum _AstronomyPlaybackSpeed { slow, normal, fast, veryFast }

enum _TimeZoneMode { approximate, real }

const int _minRouteStops = 2;
const int _maxRouteStops = 6;
const List<int> _gridStepOptions = [5, 10, 15, 20, 30, 45, 60];
const int _healthFailureThreshold = 3;
const double _stateBoundaryZoomThreshold = 3.6;
const double _cityDetailZoomThreshold = 5.6;
const Duration _astronomyPlaybackTick = Duration(milliseconds: 200);
const Duration _cityLabelRefreshDebounce = Duration(milliseconds: 220);
const List<int> _astronomyTimeZoneOffsetMinutes = [
  -720,
  -660,
  -600,
  -570,
  -540,
  -480,
  -420,
  -360,
  -300,
  -240,
  -210,
  -180,
  -120,
  -60,
  0,
  60,
  120,
  180,
  210,
  240,
  270,
  300,
  330,
  345,
  360,
  390,
  420,
  480,
  525,
  540,
  570,
  600,
  630,
  660,
  720,
  765,
  780,
  840,
];

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
  final Map<String, List<CitySearchResult>> _citySearchCache = {};
  final List<TextEditingController> _routeControllers = List.generate(
    _maxRouteStops,
    (_) => TextEditingController(),
  );

  Timer? _healthTimer;
  Timer? _astronomyTimer;
  Timer? _astronomyPlaybackTimer;
  Timer? _cityLabelRefreshTimer;
  int _consecutiveHealthFailures = 0;
  int _cityLabelRequestSequence = 0;
  int _astronomyRequestSequence = 0;
  bool _isSyncing = false;
  bool _isMapInteracting = false;
  bool _isMeasuring = false;
  bool _isLoadingAstronomy = false;
  bool _isLoadingAstronomyEvents = false;
  bool _isAstronomyPlaying = false;
  bool _showAstronomyEventPicker = false;
  bool _showSettingsPanel = false;
  double _mapViewScale = 1.0;
  bool _showGrid = true;
  bool _showTimeZones = false;
  _TimeZoneMode _timeZoneMode = _TimeZoneMode.approximate;
  bool _showLabels = true;
  bool _showShapeLabels = false;
  bool _showStateBoundaries = true;
  bool _showSunPath = true;
  bool _showMoonPath = true;
  _OuterEdgeMode _outerEdgeMode = _OuterEdgeMode.coastline;
  _AstronomyTimeMode _astronomyTimeMode = _AstronomyTimeMode.current;
  String _astronomyDisplayTimeZone = 'local';
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
  String _timezoneSource = 'unavailable';
  bool _usingRealTimezones = false;
  bool _stateBoundaryLayerLoaded = false;
  List<PlaceMarker> _markers = const [];
  List<MapShape> _shapes = const [];
  List<MapLabel> _sceneLabels = const [];
  List<MapLabel> _dynamicCityLabels = const [];
  List<MapLabel> _labels = const [];
  Rect? _visibleMapBounds;
  AstronomySnapshot? _astronomySnapshot;
  List<AstronomyEvent> _astronomyEvents = const [];
  _AstronomyEventFilter _astronomyEventFilter = _AstronomyEventFilter.all;
  String _astronomyEclipseSubtype = 'all';
  String? _selectedAstronomyEventId;
  CitySearchResult? _astronomyObserver;
  DateTime _astronomyCustomTime = DateTime.now();
  DateTime _astronomyPlaybackStart = DateTime.now();
  DateTime _astronomyPlaybackEnd = DateTime.now().add(const Duration(days: 1));
  double _astronomyPlaybackProgress = 0;
  _AstronomyPlaybackPreset _astronomyPlaybackPreset =
      _AstronomyPlaybackPreset.oneDay;
  _AstronomyPlaybackSpeed _astronomyPlaybackSpeed =
      _AstronomyPlaybackSpeed.normal;
  List<PlaceMarker?> _routePoints = List<PlaceMarker?>.filled(
    _maxRouteStops,
    null,
  );
  final List<String?> _routePointSources = List<String?>.filled(
    _maxRouteStops,
    null,
  );
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
    _astronomyPlaybackTimer?.cancel();
    _cityLabelRefreshTimer?.cancel();
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

    final requestedDetail =
        _sceneCache.isEmpty ? _interactiveSceneDetail() : _currentSceneDetail();
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
          _backendStatus =
              isHealthy ? _BackendStatus.degraded : _BackendStatus.offline;
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
          _timezoneSource = 'unavailable';
          _usingRealTimezones = false;
          _stateBoundaryLayerLoaded = false;
          _markers = const [];
          _shapes = const [];
          _sceneLabels = const [];
          _dynamicCityLabels = const [];
          _labels = const [];
          _visibleMapBounds = null;
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
          _timezoneSource = 'unavailable';
          _usingRealTimezones = false;
          _stateBoundaryLayerLoaded = false;
          _markers = const [];
          _shapes = const [];
          _sceneLabels = const [];
          _dynamicCityLabels = const [];
          _labels = const [];
          _visibleMapBounds = null;
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
      if (logicalWidth >= 420) {
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
    if (logicalWidth >= 420) {
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
    if (logicalWidth >= 420) {
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
    if (logicalWidth >= 420) {
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
      _timezoneSource = scene.timezoneSource;
      _usingRealTimezones = scene.usingRealTimezones;
      _stateBoundaryLayerLoaded = scene.shapes.any(
        (shape) => shape.role == 'state_boundary',
      );
      _markers = scene.markers;
      _shapes = scene.shapes;
      _sceneLabels = scene.labels;
      _labels = _mergeLabels(scene.labels, _dynamicCityLabels);
    });
    _scheduleDynamicCityLabelRefresh();
    if (_shouldShowAstronomy && !_isLoadingAstronomy) {
      _loadAstronomy();
    }
    if (_astronomyEvents.isEmpty && !_isLoadingAstronomyEvents) {
      _loadAstronomyEvents();
    }
  }

  List<MapLabel> _mergeLabels(
    List<MapLabel> sceneLabels,
    List<MapLabel> dynamicCityLabels,
  ) {
    if (dynamicCityLabels.isEmpty) {
      return sceneLabels;
    }

    final merged = List<MapLabel>.of(sceneLabels);
    final existingKeys = <String>{
      for (final label in sceneLabels)
        _labelMergeKey(label),
    };
    for (final label in dynamicCityLabels) {
      final key = _labelMergeKey(label);
      if (existingKeys.contains(key)) {
        continue;
      }
      existingKeys.add(key);
      merged.add(label);
    }
    return merged;
  }

  String _labelMergeKey(MapLabel label) {
    return '${label.name.toLowerCase()}|'
        '${label.x.toStringAsFixed(3)}|'
        '${label.y.toStringAsFixed(3)}';
  }

  bool _shouldLoadDynamicCityLabels() {
    return _showLabels &&
        !_isMapInteracting &&
        _mapViewScale >= _cityDetailZoomThreshold &&
        _visibleMapBounds != null &&
        _backendStatus != _BackendStatus.offline;
  }

  void _handleVisibleMapBoundsChanged(Rect bounds) {
    _visibleMapBounds = bounds;
    _scheduleDynamicCityLabelRefresh();
  }

  void _scheduleDynamicCityLabelRefresh() {
    _cityLabelRefreshTimer?.cancel();
    if (!_shouldLoadDynamicCityLabels()) {
      _cityLabelRequestSequence += 1;
      if (_dynamicCityLabels.isEmpty) {
        return;
      }
      setState(() {
        _dynamicCityLabels = const [];
        _labels = _mergeLabels(_sceneLabels, _dynamicCityLabels);
      });
      return;
    }

    final visibleBounds = _visibleMapBounds!;
    final requestSequence = ++_cityLabelRequestSequence;
    _cityLabelRefreshTimer = Timer(_cityLabelRefreshDebounce, () async {
      final paddedBounds = Rect.fromLTRB(
        visibleBounds.left - math.max(0.035, visibleBounds.width * 0.18),
        visibleBounds.top - math.max(0.035, visibleBounds.height * 0.18),
        visibleBounds.right + math.max(0.035, visibleBounds.width * 0.18),
        visibleBounds.bottom + math.max(0.035, visibleBounds.height * 0.18),
      );

      try {
        final nextLabels = await _api.loadCityLabels(
          minX: paddedBounds.left.clamp(-1.05, 1.05).toDouble(),
          maxX: paddedBounds.right.clamp(-1.05, 1.05).toDouble(),
          minY: paddedBounds.top.clamp(-1.05, 1.05).toDouble(),
          maxY: paddedBounds.bottom.clamp(-1.05, 1.05).toDouble(),
        );
        if (!mounted ||
            requestSequence != _cityLabelRequestSequence ||
            !_shouldLoadDynamicCityLabels()) {
          return;
        }
        setState(() {
          _dynamicCityLabels = nextLabels;
          _labels = _mergeLabels(_sceneLabels, _dynamicCityLabels);
        });
      } catch (_) {
        if (!mounted || requestSequence != _cityLabelRequestSequence) {
          return;
        }
      }
    });
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
    _scheduleDynamicCityLabelRefresh();
  }

  void _handleMapViewScaleChanged(double viewScale) {
    final previousShouldLoadStateBoundaries = _shouldLoadStateBoundaries();
    _mapViewScale = viewScale;
    _scheduleDynamicCityLabelRefresh();
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

  DateTime _astronomyPlaybackCurrentTime() {
    final startUtc = _astronomyPlaybackStart.toUtc();
    final endUtc = _astronomyPlaybackEnd.toUtc();
    final totalMilliseconds =
        endUtc.difference(startUtc).inMilliseconds.clamp(1, 1 << 30);
    final currentMilliseconds =
        (totalMilliseconds * _astronomyPlaybackProgress).round();
    return startUtc.add(Duration(milliseconds: currentMilliseconds)).toLocal();
  }

  Duration _astronomyPlaybackPresetDuration(_AstronomyPlaybackPreset preset) {
    return switch (preset) {
      _AstronomyPlaybackPreset.oneDay => const Duration(days: 1),
      _AstronomyPlaybackPreset.sevenDays => const Duration(days: 7),
      _AstronomyPlaybackPreset.twentyEightDays => const Duration(days: 28),
      _AstronomyPlaybackPreset.threeSixtyFiveDays => const Duration(days: 365),
      _AstronomyPlaybackPreset.fiveYears => const Duration(days: 365 * 5),
      _AstronomyPlaybackPreset.tenYears => const Duration(days: 365 * 10),
      _AstronomyPlaybackPreset.custom =>
        _astronomyPlaybackEnd.difference(_astronomyPlaybackStart),
    };
  }

  Duration _astronomyPlaybackTimeStep(_AstronomyPlaybackSpeed speed) {
    return switch (speed) {
      _AstronomyPlaybackSpeed.slow => const Duration(minutes: 5),
      _AstronomyPlaybackSpeed.normal => const Duration(minutes: 15),
      _AstronomyPlaybackSpeed.fast => const Duration(hours: 1),
      _AstronomyPlaybackSpeed.veryFast => const Duration(hours: 6),
    };
  }

  DateTime _astronomyTimestampUtc() {
    return switch (_astronomyTimeMode) {
      _AstronomyTimeMode.current => DateTime.now().toUtc(),
      _AstronomyTimeMode.custom => _astronomyCustomTime.toUtc(),
    };
  }

  void _syncAstronomyTimer() {
    _astronomyTimer?.cancel();
    if (!_shouldShowAstronomy ||
        _astronomyTimeMode != _AstronomyTimeMode.current) {
      return;
    }
    _astronomyTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _loadAstronomy(),
    );
  }

  void _stopAstronomyPlayback({bool resetProgress = false}) {
    _astronomyPlaybackTimer?.cancel();
    _astronomyPlaybackTimer = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _isAstronomyPlaying = false;
      if (resetProgress) {
        _astronomyPlaybackProgress = 0;
        _astronomyCustomTime = _astronomyPlaybackStart;
      }
    });
  }

  void _syncAstronomyPlaybackTime() {
    final startUtc = _astronomyPlaybackStart.toUtc();
    final configuredEndUtc = _astronomyPlaybackEnd.toUtc();
    final endUtc = configuredEndUtc.isAfter(startUtc)
        ? configuredEndUtc
        : startUtc.add(const Duration(minutes: 1));
    if (!endUtc.isAtSameMomentAs(configuredEndUtc)) {
      _astronomyPlaybackEnd = endUtc.toLocal();
    }
    final currentUtc = _astronomyCustomTime.toUtc();
    final totalMilliseconds =
        endUtc.difference(startUtc).inMilliseconds.clamp(1, 1 << 30);
    final elapsedMilliseconds =
        currentUtc.difference(startUtc).inMilliseconds.clamp(
              0,
              totalMilliseconds,
            );
    _astronomyPlaybackProgress = elapsedMilliseconds / totalMilliseconds;
    _astronomyCustomTime = startUtc
        .add(Duration(milliseconds: elapsedMilliseconds))
        .toLocal();
  }

  void _applyAstronomyPlaybackPreset(_AstronomyPlaybackPreset? preset) {
    if (preset == null) {
      return;
    }
    final baseTime = _astronomyTimeMode == _AstronomyTimeMode.custom
        ? _astronomyCustomTime
        : DateTime.now();
    final duration = _astronomyPlaybackPresetDuration(preset);
    setState(() {
      _astronomyPlaybackPreset = preset;
      if (preset != _AstronomyPlaybackPreset.custom) {
        final halfDuration = Duration(
          milliseconds: math.max(1, duration.inMilliseconds ~/ 2),
        );
        _astronomyPlaybackStart = baseTime.subtract(halfDuration);
        _astronomyPlaybackEnd = _astronomyPlaybackStart.add(duration);
        _astronomyTimeMode = _AstronomyTimeMode.custom;
        _astronomyCustomTime = baseTime;
        _syncAstronomyPlaybackTime();
      }
    });
    _stopAstronomyPlayback();
    _syncAstronomyTimer();
    if (_shouldShowAstronomy) {
      _loadAstronomy();
    }
  }

  void _setAstronomyPlaybackSpeed(_AstronomyPlaybackSpeed? speed) {
    if (speed == null) {
      return;
    }
    setState(() {
      _astronomyPlaybackSpeed = speed;
    });
  }

  Future<void> _pickAstronomyPlaybackDateTime({
    required BuildContext context,
    required bool isStart,
  }) async {
    final initialActual =
        isStart ? _astronomyPlaybackStart : _astronomyPlaybackEnd;
    final initial = _astronomyDisplayDateTime(initialActual.toUtc());
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2200),
    );
    if (pickedDate == null || !context.mounted) {
      return;
    }
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null || !context.mounted) {
      return;
    }
    final nextValue = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    final actualValue = _astronomyWallClockToActualTime(nextValue);
    setState(() {
      _astronomyPlaybackPreset = _AstronomyPlaybackPreset.custom;
      if (isStart) {
        _astronomyPlaybackStart = actualValue;
        if (!_astronomyPlaybackEnd.isAfter(_astronomyPlaybackStart)) {
          _astronomyPlaybackEnd =
              _astronomyPlaybackStart.add(const Duration(minutes: 1));
        }
      } else {
        _astronomyPlaybackEnd = actualValue.isAfter(_astronomyPlaybackStart)
            ? actualValue
            : _astronomyPlaybackStart.add(const Duration(minutes: 1));
      }
      _astronomyTimeMode = _AstronomyTimeMode.custom;
      _syncAstronomyPlaybackTime();
      _astronomyCustomTime = _astronomyPlaybackCurrentTime();
    });
    _stopAstronomyPlayback();
    _syncAstronomyTimer();
    if (_shouldShowAstronomy) {
      await _loadAstronomy();
    }
  }

  Future<void> _setAstronomyPlaybackProgress(double progress) async {
    final clampedProgress = progress.clamp(0.0, 1.0);
    setState(() {
      _astronomyTimeMode = _AstronomyTimeMode.custom;
      _astronomyPlaybackProgress = clampedProgress;
      _astronomyCustomTime = _astronomyPlaybackCurrentTime();
    });
    _syncAstronomyTimer();
    if (_shouldShowAstronomy) {
      await _loadAstronomy();
    }
  }

  void _toggleAstronomyPlayback() {
    if (_isAstronomyPlaying) {
      _stopAstronomyPlayback();
      return;
    }
    if (_backendStatus == _BackendStatus.offline || !_shouldShowAstronomy) {
      setState(() {
        _astronomyError =
            'Enable the sun or moon overlay and keep the backend online to use playback.';
      });
      return;
    }
    setState(() {
      _astronomyTimeMode = _AstronomyTimeMode.custom;
      _syncAstronomyPlaybackTime();
      if (_astronomyPlaybackProgress >= 1) {
        _astronomyPlaybackProgress = 0;
        _astronomyCustomTime = _astronomyPlaybackStart;
      } else {
        _astronomyCustomTime = _astronomyPlaybackCurrentTime();
      }
      _isAstronomyPlaying = true;
    });
    _syncAstronomyTimer();
    _astronomyPlaybackTimer?.cancel();
    _astronomyPlaybackTimer = Timer.periodic(
      _astronomyPlaybackTick,
      (_) async {
        if (!mounted || _isLoadingAstronomy) {
          return;
        }
        final startUtc = _astronomyPlaybackStart.toUtc();
        final configuredEndUtc = _astronomyPlaybackEnd.toUtc();
        final endUtc = configuredEndUtc.isAfter(startUtc)
            ? configuredEndUtc
            : startUtc.add(const Duration(minutes: 1));
        final totalDuration = endUtc.difference(startUtc);
        final safeTotalDuration = totalDuration.inMilliseconds <= 0
            ? const Duration(minutes: 1)
            : totalDuration;
        final nextTimeUtc = _astronomyCustomTime.toUtc().add(
          _astronomyPlaybackTimeStep(_astronomyPlaybackSpeed),
        );
        final clampedNextTimeUtc =
            nextTimeUtc.isAfter(endUtc) ? endUtc : nextTimeUtc;
        final elapsed = clampedNextTimeUtc
            .difference(startUtc)
            .inMilliseconds
            .clamp(0, safeTotalDuration.inMilliseconds);
        final nextProgress = elapsed / safeTotalDuration.inMilliseconds;
        setState(() {
          _astronomyPlaybackProgress = nextProgress;
          _astronomyCustomTime = clampedNextTimeUtc.toLocal();
        });
        await _loadAstronomy(quiet: true);
        if (!mounted || _astronomyPlaybackProgress >= 1) {
          _stopAstronomyPlayback();
        }
      },
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
        if (!_availableAstronomyEclipseSubtypes
            .contains(_astronomyEclipseSubtype)) {
          _astronomyEclipseSubtype = 'all';
        }
        if (_selectedAstronomyEventId == null && events.isNotEmpty) {
          final filtered = _filteredAstronomyEvents;
          _selectedAstronomyEventId =
              filtered.isEmpty ? null : filtered.first.id;
        } else if (_selectedAstronomyEventId != null &&
            _filteredAstronomyEvents.every(
              (event) => event.id != _selectedAstronomyEventId,
            )) {
          final filtered = _filteredAstronomyEvents;
          _selectedAstronomyEventId =
              filtered.isEmpty ? null : filtered.first.id;
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

  Future<void> _loadAstronomy({
    bool quiet = false,
    DateTime? timestampUtcOverride,
  }) async {
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
        _astronomyError =
            'Backend must be online to load the sun and moon overlay.';
      });
      return;
    }

    final requestSequence = ++_astronomyRequestSequence;
    final effectiveTimestampUtc = (timestampUtcOverride ?? _astronomyTimestampUtc())
        .toUtc();

    if (quiet) {
      _isLoadingAstronomy = true;
    } else if (mounted) {
      setState(() {
        _isLoadingAstronomy = true;
        _astronomyError = null;
      });
    }

    try {
      final observer = _astronomyObserver;
      final snapshot = await _api.loadAstronomySnapshot(
        timestampUtc: effectiveTimestampUtc,
        observerName: observer?.displayName,
        observerLatitude: observer?.latitude,
        observerLongitude: observer?.longitude,
      );
      if (!mounted || requestSequence != _astronomyRequestSequence) {
        return;
      }
      setState(() {
        _astronomySnapshot = snapshot;
        if (!quiet) {
          _astronomyError = null;
        }
      });
    } catch (_) {
      if (!mounted || requestSequence != _astronomyRequestSequence) {
        return;
      }
      setState(() {
        _astronomyError =
            'Could not load the live astronomy overlay from the backend.';
      });
      if (_isAstronomyPlaying) {
        _stopAstronomyPlayback();
      }
    } finally {
      if (quiet) {
        if (requestSequence == _astronomyRequestSequence) {
          _isLoadingAstronomy = false;
        }
      } else if (mounted) {
        if (requestSequence == _astronomyRequestSequence) {
          setState(() {
            _isLoadingAstronomy = false;
          });
        }
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
    if (!_shouldShowAstronomy) {
      _stopAstronomyPlayback();
    }
    _syncAstronomyTimer();
    if (_shouldShowAstronomy) {
      _loadAstronomy();
    }
  }

  void _setAstronomyTimeMode(_AstronomyTimeMode mode) {
    setState(() {
      _astronomyTimeMode = mode;
      if (mode == _AstronomyTimeMode.custom) {
        _syncAstronomyPlaybackTime();
        _astronomyCustomTime = _astronomyPlaybackCurrentTime();
      }
    });
    if (mode == _AstronomyTimeMode.current) {
      _stopAstronomyPlayback();
    }
    _syncAstronomyTimer();
    if (_shouldShowAstronomy) {
      _loadAstronomy();
    }
  }

  Future<void> _pickAstronomyDateTime(BuildContext context) async {
    final initialDate = _astronomyDisplayDateTime(_astronomyCustomTime.toUtc());
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2200),
    );
    if (pickedDate == null || !context.mounted) {
      return;
    }

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_astronomyCustomTime),
    );
    if (pickedTime == null || !context.mounted) {
      return;
    }

    final selectedWallClock = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() {
      _astronomyCustomTime = _astronomyWallClockToActualTime(selectedWallClock);
      _syncAstronomyPlaybackTime();
    });

    _stopAstronomyPlayback();
    if (_shouldShowAstronomy) {
      _loadAstronomy();
    }
  }

  Future<List<CitySearchResult>> _searchCities(String query) async {
    final cacheKey = query.trim().toLowerCase();
    final cached = _citySearchCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    if (_backendStatus == _BackendStatus.offline) {
      return const [];
    }

    try {
      final results = await _api.searchCities(query: query, limit: 12);
      _citySearchCache[cacheKey] = results;
      return results;
    } catch (_) {
      return const [];
    }
  }

  void _setAstronomyObserver(CitySearchResult? observer) {
    setState(() {
      _astronomyObserver = observer;
      _astronomyObserverController.text = observer?.displayName ?? '';
    });
    if (_shouldShowAstronomy) {
      _loadAstronomy();
    }
  }

  List<_ChoiceItem<String>> get _astronomyDisplayTimeZoneOptions => [
        const _ChoiceItem<String>(
          value: 'local',
          label: 'Local device time',
        ),
        for (final offsetMinutes in _astronomyTimeZoneOffsetMinutes)
          _ChoiceItem<String>(
            value: _astronomyTimeZoneValueForOffset(offsetMinutes),
            label: _formatAstronomyOffsetLabel(offsetMinutes),
          ),
      ];

  String _astronomyTimeZoneValueForOffset(int offsetMinutes) {
    return 'offset:$offsetMinutes';
  }

  int? _selectedAstronomyOffsetMinutes() {
    if (_astronomyDisplayTimeZone == 'local') {
      return null;
    }
    final parts = _astronomyDisplayTimeZone.split(':');
    if (parts.length != 2 || parts.first != 'offset') {
      return null;
    }
    return int.tryParse(parts.last);
  }

  String _formatAstronomyOffsetLabel(int offsetMinutes) {
    if (offsetMinutes == 0) {
      return 'UTC';
    }

    final sign = offsetMinutes >= 0 ? '+' : '-';
    final absoluteMinutes = offsetMinutes.abs();
    final hours = absoluteMinutes ~/ 60;
    final minutes = absoluteMinutes % 60;
    final hourLabel = hours.toString().padLeft(2, '0');
    if (minutes == 0) {
      return 'UTC$sign$hourLabel';
    }
    return 'UTC$sign$hourLabel:${minutes.toString().padLeft(2, '0')}';
  }

  String _astronomyDisplayTimeZoneLabel() {
    final offsetMinutes = _selectedAstronomyOffsetMinutes();
    if (offsetMinutes == null) {
      return 'Local';
    }
    return _formatAstronomyOffsetLabel(offsetMinutes);
  }

  DateTime _astronomyDisplayDateTime(DateTime timestampUtc) {
    final utc = timestampUtc.toUtc();
    final offsetMinutes = _selectedAstronomyOffsetMinutes();
    if (offsetMinutes == null) {
      return utc.toLocal();
    }
    return utc.add(Duration(minutes: offsetMinutes));
  }

  DateTime _astronomyWallClockToActualTime(DateTime wallClock) {
    final offsetMinutes = _selectedAstronomyOffsetMinutes();
    if (offsetMinutes == null) {
      return wallClock;
    }
    final utc = DateTime.utc(
      wallClock.year,
      wallClock.month,
      wallClock.day,
      wallClock.hour,
      wallClock.minute,
    ).subtract(Duration(minutes: offsetMinutes));
    return utc.toLocal();
  }

  String _formatAstronomyTimeLabel(DateTime timestampUtc) {
    final display = _astronomyDisplayDateTime(timestampUtc);
    final hour = display.hour == 0
        ? 12
        : (display.hour > 12 ? display.hour - 12 : display.hour);
    final minute = display.minute.toString().padLeft(2, '0');
    final meridiem = display.hour >= 12 ? 'PM' : 'AM';
    return '${display.month}/${display.day}/${display.year} $hour:$minute $meridiem ${_astronomyDisplayTimeZoneLabel()}';
  }

  List<AstronomyEvent> get _eventFilterMatchedAstronomyEvents {
    return switch (_astronomyEventFilter) {
      _AstronomyEventFilter.all => _astronomyEvents,
      _AstronomyEventFilter.solar => _astronomyEvents
          .where((event) => event.isSolar)
          .toList(growable: false),
      _AstronomyEventFilter.lunar => _astronomyEvents
          .where((event) => event.isLunar)
          .toList(growable: false),
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
    final eventTime = event.timestampUtc.toLocal();
    final currentDurationUtc = _astronomyPlaybackEnd
        .toUtc()
        .difference(_astronomyPlaybackStart.toUtc());
    final safeDuration = currentDurationUtc.inMilliseconds <= 0
        ? const Duration(days: 1)
        : currentDurationUtc;
    final halfDuration = Duration(
      milliseconds: math.max(1, safeDuration.inMilliseconds ~/ 2),
    );
    setState(() {
      _astronomyTimeMode = _AstronomyTimeMode.custom;
      _astronomyPlaybackStart = eventTime.subtract(halfDuration);
      _astronomyPlaybackEnd = _astronomyPlaybackStart.add(safeDuration);
      _astronomyCustomTime = eventTime;
      _selectedAstronomyEventId = event.id;
      _showSunPath = true;
      _showMoonPath = true;
      _showAstronomyEventPicker = false;
      _syncAstronomyPlaybackTime();
    });
    _stopAstronomyPlayback();
    _syncAstronomyTimer();
    await _loadAstronomy(timestampUtcOverride: event.timestampUtc);
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

  Future<void> _setRouteStopFromSearchResult(
    CitySearchResult entry,
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
        name: entry.displayName,
        latitude: entry.latitude,
        longitude: entry.longitude,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _routePoints[stopIndex] = marker;
        _routePointSources[stopIndex] = entry.displayName;
        _routeControllers[stopIndex].text = entry.displayName;
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

  List<PlaceMarker?> get _activeRoutePoints =>
      _routePoints.take(_stopCount).toList();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompactScreen = constraints.maxWidth < 720;
        final panelInset = isCompactScreen ? 8.0 : 20.0;
        final panelTopOffset = panelInset + (isCompactScreen ? 106.0 : 64.0);
        final panelWidth = math.min(
          isCompactScreen
              ? 340.0
              : (constraints.maxWidth >= 1280 ? 420.0 : 380.0),
          math.max(260.0, constraints.maxWidth - (panelInset * 2)),
        );
        final mapPadding = isCompactScreen ? 4.0 : 20.0;
        final hudInset = isCompactScreen ? 10.0 : 20.0;
        final overlayNotice = _pickStopIndex != null
            ? 'Tap the map to place stop ${_pickStopIndex! + 1}.'
            : _error ?? _measureError ?? _astronomyError;
        final overlayNoticeIsWarning =
            _pickStopIndex == null && overlayNotice != null;
        final showBottomNotice = !isCompactScreen || overlayNotice != null;

        final intro = _IntroPanel(
          showGrid: _showGrid,
          showTimeZones: _showTimeZones,
          timeZoneMode: _timeZoneMode,
          gridStepDegrees: _gridStepDegrees,
          outerEdgeMode: _outerEdgeMode,
          showLabels: _showLabels,
          showShapeLabels: _showShapeLabels,
          showStateBoundaries: _showStateBoundaries,
          showSunPath: _showSunPath,
          showMoonPath: _showMoonPath,
          astronomyTimeMode: _astronomyTimeMode,
          astronomyDisplayTimeZone: _astronomyDisplayTimeZone,
          astronomyDisplayTimeZoneOptions: _astronomyDisplayTimeZoneOptions,
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
          timezoneSource: _timezoneSource,
          usingRealTimezones: _usingRealTimezones,
          astronomySnapshot: _astronomySnapshot,
          astronomyEvents: _filteredAstronomyEvents,
          selectedAstronomyEvent: _selectedAstronomyEvent,
          astronomyEventFilter: _astronomyEventFilter,
          astronomyEclipseSubtype: _astronomyEclipseSubtype,
          astronomyEclipseSubtypeOptions: _availableAstronomyEclipseSubtypes,
          showAstronomyEventPicker: _showAstronomyEventPicker,
          astronomyObserverController: _astronomyObserverController,
          onSearchCities: _searchCities,
          astronomyEventScrollController: _astronomyEventScrollController,
          astronomyObserverName: _astronomyObserver?.displayName,
          astronomyCustomTimeLabel: _formatAstronomyTimeLabel(
            _astronomyCustomTime.toUtc(),
          ),
          astronomyPlaybackStartLabel: _formatAstronomyTimeLabel(
            _astronomyPlaybackStart.toUtc(),
          ),
          astronomyPlaybackEndLabel: _formatAstronomyTimeLabel(
            _astronomyPlaybackEnd.toUtc(),
          ),
          astronomyPlaybackCurrentLabel: _formatAstronomyTimeLabel(
            _astronomyCustomTime.toUtc(),
          ),
          astronomyPlaybackProgress: _astronomyPlaybackProgress,
          astronomyPlaybackPreset: _astronomyPlaybackPreset,
          astronomyPlaybackSpeed: _astronomyPlaybackSpeed,
          isAstronomyPlaying: _isAstronomyPlaying,
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
          onShowTimeZonesChanged: (value) => setState(() {
            _showTimeZones = value;
            _timeZoneMode = _TimeZoneMode.approximate;
          }),
          onTimeZoneModeChanged: (value) {
            if (value == null || value != _TimeZoneMode.approximate) {
              return;
            }
            setState(() {
              _timeZoneMode = value;
            });
          },
          onGridStepChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() {
              _gridStepDegrees = value;
            });
          },
          onShowLabelsChanged: (value) {
            setState(() {
              _showLabels = value;
            });
            _scheduleDynamicCityLabelRefresh();
          },
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
          onShowSunPathChanged: (value) =>
              _setAstronomyToggle(showSunPath: value),
          onShowMoonPathChanged: (value) =>
              _setAstronomyToggle(showMoonPath: value),
          onAstronomyTimeModeChanged: (value) {
            if (value == null) {
              return;
            }
            _setAstronomyTimeMode(value);
          },
          onAstronomyDisplayTimeZoneChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() {
              _astronomyDisplayTimeZone = value;
            });
          },
          onAstronomyDateTimePressed: () => _pickAstronomyDateTime(context),
          onAstronomyObserverSelected: _setAstronomyObserver,
          onClearAstronomyObserver: () => _setAstronomyObserver(null),
          onAstronomyPlaybackPresetChanged: _applyAstronomyPlaybackPreset,
          onAstronomyPlaybackSpeedChanged: _setAstronomyPlaybackSpeed,
          onAstronomyPlaybackStartPressed: () => _pickAstronomyPlaybackDateTime(
            context: context,
            isStart: true,
          ),
          onAstronomyPlaybackEndPressed: () => _pickAstronomyPlaybackDateTime(
            context: context,
            isStart: false,
          ),
          onAstronomyPlaybackProgressChanged: (value) {
            _setAstronomyPlaybackProgress(value);
          },
          onAstronomyPlaybackToggle: _toggleAstronomyPlayback,
          onAstronomyPlaybackStop: () =>
              _stopAstronomyPlayback(resetProgress: true),
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
          onStopCitySelected: _setRouteStopFromSearchResult,
          onPickStop: _setPickStop,
          onClearRoute: () => setState(() {
            _clearRoutePlanner();
          }),
        );

        final mapCard = Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(mapPadding),
                  child: LayoutBuilder(
                    builder: (context, mapConstraints) {
                      final mapCanvas = FlatWorldCanvas(
                        tileBaseUrl: _api.baseUrl,
                        markers: _markers,
                        shapes: _shapes,
                        labels: _labels,
                        showGrid: _showGrid,
                        showTimeZones: _showTimeZones,
                        useRealTimeZones: _timeZoneMode == _TimeZoneMode.real,
                        gridStepDegrees: _gridStepDegrees,
                        edgeRenderMode: switch (_outerEdgeMode) {
                          _OuterEdgeMode.coastline => EdgeRenderMode.coastline,
                          _OuterEdgeMode.country => EdgeRenderMode.country,
                          _OuterEdgeMode.both => EdgeRenderMode.both,
                        },
                        showLabels: _showLabels,
                        showShapeLabels: _showShapeLabels,
                        showStateBoundaries: _showStateBoundaries &&
                            _mapViewScale >= _stateBoundaryZoomThreshold,
                        astronomySnapshot: _astronomySnapshot,
                        showSunPath: _showSunPath,
                        showMoonPath: _showMoonPath,
                        astronomyObserverName: _astronomyObserver?.displayName,
                        routePoints: _activeRoutePoints,
                        activePickLabel: _pickStopIndex == null
                            ? null
                            : '${_pickStopIndex! + 1}',
                        onMapPointPicked: _setRouteStopFromMap,
                        onInteractionChanged: _handleMapInteractionChanged,
                        onViewScaleChanged: _handleMapViewScaleChanged,
                        onVisibleMapBoundsChanged:
                            _handleVisibleMapBoundsChanged,
                      );
                      final mapSize = math.min(
                        mapConstraints.maxWidth,
                        mapConstraints.maxHeight,
                      );
                      return Align(
                        alignment: Alignment.center,
                        child: SizedBox.square(
                          dimension: mapSize,
                          child: mapCanvas,
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                top: hudInset,
                left: hudInset,
                right: null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF112A46),
                        foregroundColor: const Color(0xFFF8F3E8),
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompactScreen ? 14 : 16,
                          vertical: isCompactScreen ? 12 : 14,
                        ),
                      ),
                      onPressed: () => setState(() {
                        _showSettingsPanel = !_showSettingsPanel;
                      }),
                      icon: Icon(
                        _showSettingsPanel ? Icons.close : Icons.tune,
                      ),
                      label: Text(
                        _showSettingsPanel ? 'Close settings' : 'Settings',
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (isCompactScreen)
                      _StatusRow(status: _backendStatus, compact: true)
                    else ...[
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompactScreen ? 12 : 14,
                          vertical: isCompactScreen ? 8 : 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xEAF8F3E8),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFD7E0E5)),
                        ),
                        child: const Text(
                          'Maybeflat map',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF112A46),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _StatusRow(status: _backendStatus),
                    ],
                  ],
                ),
              ),
              if (isCompactScreen)
                Positioned(
                  top: hudInset,
                  left: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xEAF8F3E8),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFD7E0E5)),
                        ),
                        child: const Text(
                          'Maybeflat map',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF112A46),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (showBottomNotice)
                Positioned(
                  left: hudInset,
                  right: hudInset,
                  bottom: hudInset,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isCompactScreen ? 250 : 460,
                      ),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompactScreen ? 14 : 16,
                          vertical: isCompactScreen ? 10 : 12,
                        ),
                        decoration: BoxDecoration(
                          color: overlayNoticeIsWarning
                              ? const Color(0xF6F5E6C8)
                              : const Color(0xEAF8F3E8),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: overlayNoticeIsWarning
                                ? const Color(0xFFE0C38B)
                                : const Color(0xFFD7E0E5),
                          ),
                        ),
                        child: Text(
                          overlayNotice ??
                              'Open settings to change layers, astronomy overlays, and route tools.',
                          style: TextStyle(
                            fontSize: isCompactScreen ? 12 : 13,
                            height: 1.4,
                            color: overlayNoticeIsWarning
                                ? const Color(0xFF7A4A17)
                                : const Color(0xFF335C67),
                            fontWeight: overlayNoticeIsWarning
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );

        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(panelInset),
              child: Stack(
                children: [
                  Positioned.fill(child: mapCard),
                  if (_showSettingsPanel)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () => setState(() => _showSettingsPanel = false),
                        child: Container(
                          color: const Color(0x330E1C26),
                        ),
                      ),
                    ),
                  Positioned(
                    top: panelTopOffset,
                    bottom: panelInset,
                    left: panelInset,
                    right: null,
                    child: IgnorePointer(
                      ignoring: !_showSettingsPanel,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        offset: _showSettingsPanel
                            ? Offset.zero
                            : const Offset(-1.08, 0),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          opacity: _showSettingsPanel ? 1 : 0,
                          child: SizedBox(
                            width: panelWidth,
                            child: intro,
                          ),
                        ),
                      ),
                    ),
                  ),
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
    required this.showTimeZones,
    required this.timeZoneMode,
    required this.gridStepDegrees,
    required this.outerEdgeMode,
    required this.showLabels,
    required this.showShapeLabels,
    required this.showStateBoundaries,
    required this.showSunPath,
    required this.showMoonPath,
    required this.astronomyTimeMode,
    required this.astronomyDisplayTimeZone,
    required this.astronomyDisplayTimeZoneOptions,
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
    required this.timezoneSource,
    required this.usingRealTimezones,
    required this.astronomySnapshot,
    required this.astronomyEvents,
    required this.selectedAstronomyEvent,
    required this.astronomyEventFilter,
    required this.astronomyEclipseSubtype,
    required this.astronomyEclipseSubtypeOptions,
    required this.showAstronomyEventPicker,
    required this.astronomyObserverController,
    required this.onSearchCities,
    required this.astronomyEventScrollController,
    required this.astronomyObserverName,
    required this.astronomyCustomTimeLabel,
    required this.astronomyPlaybackStartLabel,
    required this.astronomyPlaybackEndLabel,
    required this.astronomyPlaybackCurrentLabel,
    required this.astronomyPlaybackProgress,
    required this.astronomyPlaybackPreset,
    required this.astronomyPlaybackSpeed,
    required this.isAstronomyPlaying,
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
    required this.onShowTimeZonesChanged,
    required this.onTimeZoneModeChanged,
    required this.onGridStepChanged,
    required this.onOuterEdgeModeChanged,
    required this.onShowLabelsChanged,
    required this.onShowShapeLabelsChanged,
    required this.onShowStateBoundariesChanged,
    required this.onShowSunPathChanged,
    required this.onShowMoonPathChanged,
    required this.onAstronomyTimeModeChanged,
    required this.onAstronomyDisplayTimeZoneChanged,
    required this.onAstronomyDateTimePressed,
    required this.onAstronomyObserverSelected,
    required this.onClearAstronomyObserver,
    required this.onAstronomyPlaybackPresetChanged,
    required this.onAstronomyPlaybackSpeedChanged,
    required this.onAstronomyPlaybackStartPressed,
    required this.onAstronomyPlaybackEndPressed,
    required this.onAstronomyPlaybackProgressChanged,
    required this.onAstronomyPlaybackToggle,
    required this.onAstronomyPlaybackStop,
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
  final bool showTimeZones;
  final _TimeZoneMode timeZoneMode;
  final int gridStepDegrees;
  final _OuterEdgeMode outerEdgeMode;
  final bool showLabels;
  final bool showShapeLabels;
  final bool showStateBoundaries;
  final bool showSunPath;
  final bool showMoonPath;
  final _AstronomyTimeMode astronomyTimeMode;
  final String astronomyDisplayTimeZone;
  final List<_ChoiceItem<String>> astronomyDisplayTimeZoneOptions;
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
  final String timezoneSource;
  final bool usingRealTimezones;
  final AstronomySnapshot? astronomySnapshot;
  final List<AstronomyEvent> astronomyEvents;
  final AstronomyEvent? selectedAstronomyEvent;
  final _AstronomyEventFilter astronomyEventFilter;
  final String astronomyEclipseSubtype;
  final List<String> astronomyEclipseSubtypeOptions;
  final bool showAstronomyEventPicker;
  final TextEditingController astronomyObserverController;
  final Future<List<CitySearchResult>> Function(String query) onSearchCities;
  final ScrollController astronomyEventScrollController;
  final String? astronomyObserverName;
  final String astronomyCustomTimeLabel;
  final String astronomyPlaybackStartLabel;
  final String astronomyPlaybackEndLabel;
  final String astronomyPlaybackCurrentLabel;
  final double astronomyPlaybackProgress;
  final _AstronomyPlaybackPreset astronomyPlaybackPreset;
  final _AstronomyPlaybackSpeed astronomyPlaybackSpeed;
  final bool isAstronomyPlaying;
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
  final ValueChanged<bool> onShowTimeZonesChanged;
  final ValueChanged<_TimeZoneMode?> onTimeZoneModeChanged;
  final ValueChanged<int?> onGridStepChanged;
  final ValueChanged<_OuterEdgeMode?> onOuterEdgeModeChanged;
  final ValueChanged<bool> onShowLabelsChanged;
  final ValueChanged<bool> onShowShapeLabelsChanged;
  final ValueChanged<bool> onShowStateBoundariesChanged;
  final ValueChanged<bool> onShowSunPathChanged;
  final ValueChanged<bool> onShowMoonPathChanged;
  final ValueChanged<_AstronomyTimeMode?> onAstronomyTimeModeChanged;
  final ValueChanged<String?> onAstronomyDisplayTimeZoneChanged;
  final VoidCallback onAstronomyDateTimePressed;
  final ValueChanged<CitySearchResult?> onAstronomyObserverSelected;
  final VoidCallback onClearAstronomyObserver;
  final ValueChanged<_AstronomyPlaybackPreset?>
      onAstronomyPlaybackPresetChanged;
  final ValueChanged<_AstronomyPlaybackSpeed?> onAstronomyPlaybackSpeedChanged;
  final VoidCallback onAstronomyPlaybackStartPressed;
  final VoidCallback onAstronomyPlaybackEndPressed;
  final ValueChanged<double> onAstronomyPlaybackProgressChanged;
  final VoidCallback onAstronomyPlaybackToggle;
  final VoidCallback onAstronomyPlaybackStop;
  final ValueChanged<_AstronomyEventFilter?> onAstronomyEventFilterChanged;
  final ValueChanged<String?> onAstronomyEclipseSubtypeChanged;
  final ValueChanged<AstronomyEvent?> onAstronomyEventSelected;
  final VoidCallback onToggleAstronomyEventPicker;
  final VoidCallback onPreviousAstronomyEvent;
  final VoidCallback onNextAstronomyEvent;
  final Future<void> Function() onReload;
  final ValueChanged<_DistanceUnitDisplay?> onDistanceUnitDisplayChanged;
  final ValueChanged<int?> onStopCountChanged;
  final void Function(CitySearchResult entry, int stopIndex) onStopCitySelected;
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
              _CollapsiblePanel(
                title: 'Map Controls',
                subtitle: 'Grid, time zones, labels, and boundaries',
                initiallyExpanded: false,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: showGrid,
                    title: const Text('Show lat/lon grid'),
                    onChanged: onShowGridChanged,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: showTimeZones,
                    title: const Text('Show time zones'),
                    subtitle: const Text(
                      'Approximate UTC wedges from longitude',
                    ),
                    onChanged: onShowTimeZonesChanged,
                  ),
                  _SelectionField(
                    labelText: 'Time-zone mode',
                    valueText: 'Approximate',
                    enabled: showTimeZones,
                    currentValue: _TimeZoneMode.approximate,
                    onChanged: onTimeZoneModeChanged,
                    options: const [
                      _ChoiceItem(
                        value: _TimeZoneMode.approximate,
                        label: 'Approximate',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Real time zones are blocked for now. Approximate mode remains available.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF335C67),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SelectionField(
                    labelText: 'Grid interval',
                    valueText: '$gridStepDegrees degrees',
                    helperText: 'Multiples of 5 degrees',
                    enabled: showGrid,
                    currentValue: gridStepDegrees,
                    onChanged: onGridStepChanged,
                    options: [
                      for (final step in _gridStepOptions)
                        _ChoiceItem(value: step, label: '$step degrees'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SelectionField(
                    labelText: 'Outer edge source',
                    valueText: switch (outerEdgeMode) {
                      _OuterEdgeMode.coastline => 'Coastline',
                      _OuterEdgeMode.country => 'Country',
                      _OuterEdgeMode.both => 'Both',
                    },
                    currentValue: outerEdgeMode,
                    onChanged: onOuterEdgeModeChanged,
                    options: const [
                      _ChoiceItem(
                        value: _OuterEdgeMode.coastline,
                        label: 'Coastline',
                      ),
                      _ChoiceItem(
                        value: _OuterEdgeMode.country,
                        label: 'Country',
                      ),
                      _ChoiceItem(value: _OuterEdgeMode.both, label: 'Both'),
                    ],
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
                ],
              ),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 18),
              _CollapsiblePanel(
                title: 'Astronomy Overlay',
                subtitle: 'Sun, moon, observer, and event controls',
                initiallyExpanded: false,
                children: [
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
                  _SelectionField(
                    labelText: 'Astronomy time',
                    valueText: astronomyTimeMode == _AstronomyTimeMode.current
                        ? 'Current time'
                        : 'Custom time',
                    currentValue: astronomyTimeMode,
                    onChanged: onAstronomyTimeModeChanged,
                    options: const [
                      _ChoiceItem(
                        value: _AstronomyTimeMode.current,
                        label: 'Current time',
                      ),
                      _ChoiceItem(
                        value: _AstronomyTimeMode.custom,
                        label: 'Custom time',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _SelectionField(
                    labelText: 'Display time zone',
                    valueText: astronomyDisplayTimeZoneOptions
                            .firstWhere(
                              (option) =>
                                  option.value == astronomyDisplayTimeZone,
                              orElse: () =>
                                  astronomyDisplayTimeZoneOptions.first,
                            )
                            .label,
                    helperText:
                        'Default is local time. Fixed UTC offsets are display-only.',
                    currentValue: astronomyDisplayTimeZone,
                    onChanged: onAstronomyDisplayTimeZoneChanged,
                    options: astronomyDisplayTimeZoneOptions,
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
                    searchCities: onSearchCities,
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
                  const SizedBox(height: 14),
                  const Text(
                    'Sun/Moon playback',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF112A46),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SelectionField(
                    labelText: 'Range',
                    valueText:
                        _formatPlaybackPresetLabel(astronomyPlaybackPreset),
                    currentValue: astronomyPlaybackPreset,
                    onChanged: onAstronomyPlaybackPresetChanged,
                    options: [
                      for (final preset in _AstronomyPlaybackPreset.values)
                        _ChoiceItem(
                          value: preset,
                          label: _formatPlaybackPresetLabel(preset),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _SelectionField(
                    labelText: 'Playback speed',
                    valueText:
                        _formatPlaybackSpeedLabel(astronomyPlaybackSpeed),
                    currentValue: astronomyPlaybackSpeed,
                    onChanged: onAstronomyPlaybackSpeedChanged,
                    options: [
                      for (final speed in _AstronomyPlaybackSpeed.values)
                        _ChoiceItem(
                          value: speed,
                          label: _formatPlaybackSpeedLabel(speed),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onAstronomyPlaybackStartPressed,
                          child: Text('Start: $astronomyPlaybackStartLabel'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onAstronomyPlaybackEndPressed,
                          child: Text('End: $astronomyPlaybackEndLabel'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scrub time: $astronomyPlaybackCurrentLabel',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF335C67),
                          height: 1.35,
                        ),
                      ),
                      Slider(
                        value: astronomyPlaybackProgress,
                        onChanged: onAstronomyPlaybackProgressChanged,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF112A46),
                            foregroundColor: const Color(0xFFF8F3E8),
                          ),
                          onPressed: onAstronomyPlaybackToggle,
                          child: Text(isAstronomyPlaying ? 'Pause' : 'Play'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isAstronomyPlaying ||
                                  astronomyPlaybackProgress > 0
                              ? onAstronomyPlaybackStop
                              : null,
                          child: const Text('Restart'),
                        ),
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
                              _formatObserverSummary(
                                  astronomySnapshot!.observer!),
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
                  _SelectionField(
                    labelText: 'Event Filter',
                    valueText: switch (astronomyEventFilter) {
                      _AstronomyEventFilter.all => 'All eclipses',
                      _AstronomyEventFilter.solar => 'Solar eclipses',
                      _AstronomyEventFilter.lunar => 'Lunar eclipses',
                    },
                    currentValue: astronomyEventFilter,
                    onChanged: onAstronomyEventFilterChanged,
                    options: const [
                      _ChoiceItem(
                        value: _AstronomyEventFilter.all,
                        label: 'All eclipses',
                      ),
                      _ChoiceItem(
                        value: _AstronomyEventFilter.solar,
                        label: 'Solar eclipses',
                      ),
                      _ChoiceItem(
                        value: _AstronomyEventFilter.lunar,
                        label: 'Lunar eclipses',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _SelectionField(
                    labelText: 'Eclipse Type',
                    valueText:
                        _formatEclipseSubtypeOption(astronomyEclipseSubtype),
                    currentValue: astronomyEclipseSubtype,
                    onChanged: onAstronomyEclipseSubtypeChanged,
                    options: [
                      for (final subtype in astronomyEclipseSubtypeOptions)
                        _ChoiceItem(
                          value: subtype,
                          label: _formatEclipseSubtypeOption(subtype),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: astronomyEvents.isEmpty
                        ? null
                        : onToggleAstronomyEventPicker,
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
                  if (showAstronomyEventPicker &&
                      astronomyEvents.isNotEmpty) ...[
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                          onPressed: astronomyEvents.isEmpty
                              ? null
                              : onNextAstronomyEvent,
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
                ],
              ),
              const SizedBox(height: 12),
              _CollapsiblePanel(
                title: 'Scene Data',
                subtitle: 'Backend reload and source details',
                initiallyExpanded: false,
                children: [
                  FilledButton(
                    onPressed: isLoading ? null : () => onReload(),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF112A46),
                      foregroundColor: const Color(0xFFF8F3E8),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(
                      isLoading
                          ? 'Loading backend scene...'
                          : 'Reload backend scene',
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
                ],
              ),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 18),
              _CollapsiblePanel(
                title: 'Route Planner',
                subtitle: 'Cities, map picks, and ordered route distance',
                initiallyExpanded: false,
                children: [
                  _SelectionField(
                    labelText: 'Distance units',
                    valueText: switch (distanceUnitDisplay) {
                      _DistanceUnitDisplay.both => 'Both',
                      _DistanceUnitDisplay.kilometers => 'Kilometers',
                      _DistanceUnitDisplay.miles => 'Miles',
                    },
                    currentValue: distanceUnitDisplay,
                    onChanged: onDistanceUnitDisplayChanged,
                    options: const [
                      _ChoiceItem(
                        value: _DistanceUnitDisplay.both,
                        label: 'Both',
                      ),
                      _ChoiceItem(
                        value: _DistanceUnitDisplay.kilometers,
                        label: 'Kilometers',
                      ),
                      _ChoiceItem(
                        value: _DistanceUnitDisplay.miles,
                        label: 'Miles',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SelectionField(
                    labelText: 'How many stops',
                    valueText: '$stopCount stops',
                    currentValue: stopCount,
                    onChanged: onStopCountChanged,
                    options: [
                      for (var count = _minRouteStops;
                          count <= _maxRouteStops;
                          count += 1)
                        _ChoiceItem(value: count, label: '$count stops'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (var index = 0; index < stopCount; index += 1) ...[
                    _CitySearchField(
                      label: 'Stop ${index + 1} city',
                      controller: stopControllers[index],
                      searchCities: onSearchCities,
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
                  if (_routeReady(stopSources, stopCount) &&
                      routeLegs.isNotEmpty) ...[
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
                            _totalDistanceSummary(
                                routeLegs, distanceUnitDisplay),
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
                          for (var index = 0;
                              index < routeLegs.length;
                              index += 1)
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
                ],
              ),
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

  int? _selectedAstronomyOffsetMinutes() {
    if (astronomyDisplayTimeZone == 'local') {
      return null;
    }
    final parts = astronomyDisplayTimeZone.split(':');
    if (parts.length != 2 || parts.first != 'offset') {
      return null;
    }
    return int.tryParse(parts.last);
  }

  String _formatAstronomyOffsetLabel(int offsetMinutes) {
    if (offsetMinutes == 0) {
      return 'UTC';
    }

    final sign = offsetMinutes >= 0 ? '+' : '-';
    final absoluteMinutes = offsetMinutes.abs();
    final hours = absoluteMinutes ~/ 60;
    final minutes = absoluteMinutes % 60;
    final hourLabel = hours.toString().padLeft(2, '0');
    if (minutes == 0) {
      return 'UTC$sign$hourLabel';
    }
    return 'UTC$sign$hourLabel:${minutes.toString().padLeft(2, '0')}';
  }

  String _astronomyDisplayTimeZoneLabel() {
    final offsetMinutes = _selectedAstronomyOffsetMinutes();
    if (offsetMinutes == null) {
      return 'Local';
    }
    return _formatAstronomyOffsetLabel(offsetMinutes);
  }

  DateTime _astronomyDisplayDateTime(DateTime timestampUtc) {
    final utc = timestampUtc.toUtc();
    final offsetMinutes = _selectedAstronomyOffsetMinutes();
    if (offsetMinutes == null) {
      return utc.toLocal();
    }
    return utc.add(Duration(minutes: offsetMinutes));
  }

  String _formatSnapshotTime(AstronomySnapshot snapshot) {
    final display = _astronomyDisplayDateTime(snapshot.timestampUtc);
    final minute = display.minute.toString().padLeft(2, '0');
    return '${display.month}/${display.day}/${display.year} ${display.hour.toString().padLeft(2, '0')}:$minute ${_astronomyDisplayTimeZoneLabel()}';
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
    final moonLabel =
        observer.isMoonVisible ? 'Moon above horizon' : 'Moon below horizon';
    return '${observer.name ?? 'Observer'}: $daylightLabel, sun ${observer.sunAltitudeDegrees.toStringAsFixed(1)} deg, moon ${observer.moonAltitudeDegrees.toStringAsFixed(1)} deg, $moonLabel.';
  }

  String _formatPlaybackPresetLabel(_AstronomyPlaybackPreset preset) {
    return switch (preset) {
      _AstronomyPlaybackPreset.oneDay => '1 day',
      _AstronomyPlaybackPreset.sevenDays => '7 days',
      _AstronomyPlaybackPreset.twentyEightDays => '28 days',
      _AstronomyPlaybackPreset.threeSixtyFiveDays => '365 days',
      _AstronomyPlaybackPreset.fiveYears => '5 years',
      _AstronomyPlaybackPreset.tenYears => '10 years',
      _AstronomyPlaybackPreset.custom => 'Custom',
    };
  }

  String _formatPlaybackSpeedLabel(_AstronomyPlaybackSpeed speed) {
    return switch (speed) {
      _AstronomyPlaybackSpeed.slow => 'Slow',
      _AstronomyPlaybackSpeed.normal => 'Normal',
      _AstronomyPlaybackSpeed.fast => 'Fast',
      _AstronomyPlaybackSpeed.veryFast => 'Very fast',
    };
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
    final display = _astronomyDisplayDateTime(event.timestampUtc);
    final minute = display.minute.toString().padLeft(2, '0');
    final meridiem = display.hour >= 12 ? 'PM' : 'AM';
    final hour = display.hour == 0
        ? 12
        : (display.hour > 12 ? display.hour - 12 : display.hour);
    return '${display.month}/${display.day}/${display.year} $hour:$minute $meridiem ${_astronomyDisplayTimeZoneLabel()}';
  }
}

class _CollapsiblePanel extends StatefulWidget {
  const _CollapsiblePanel({
    required this.title,
    required this.children,
    this.subtitle,
    this.initiallyExpanded = false,
  });

  final String title;
  final String? subtitle;
  final bool initiallyExpanded;
  final List<Widget> children;

  @override
  State<_CollapsiblePanel> createState() => _CollapsiblePanelState();
}

class _CollapsiblePanelState extends State<_CollapsiblePanel> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F3E8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E0E5)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF112A46),
                          ),
                        ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.subtitle!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF335C67),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF335C67),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.children,
              ),
            ),
        ],
      ),
    );
  }
}

class _ChoiceItem<T> {
  const _ChoiceItem({
    required this.value,
    required this.label,
    this.subtitle,
  });

  final T value;
  final String label;
  final String? subtitle;
}

class _SelectionField<T> extends StatefulWidget {
  const _SelectionField({
    required this.labelText,
    required this.valueText,
    required this.currentValue,
    required this.options,
    required this.onChanged,
    this.helperText,
    this.enabled = true,
  });

  final String labelText;
  final String valueText;
  final String? helperText;
  final T? currentValue;
  final List<_ChoiceItem<T>> options;
  final ValueChanged<T?> onChanged;
  final bool enabled;

  @override
  State<_SelectionField<T>> createState() => _SelectionFieldState<T>();
}

class _SelectionFieldState<T> extends State<_SelectionField<T>> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _SelectionField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _expanded) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor =
        widget.enabled ? const Color(0xFFBFCBD5) : const Color(0xFFD7E0E5);
    final textColor =
        widget.enabled ? const Color(0xFF112A46) : const Color(0xFF7B8B94);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: widget.enabled
              ? () => setState(() => _expanded = !_expanded)
              : null,
          borderRadius: BorderRadius.circular(4),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: widget.labelText,
              helperText: widget.helperText,
              border: const OutlineInputBorder(),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: borderColor),
                borderRadius: BorderRadius.circular(4),
              ),
              disabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: borderColor),
                borderRadius: BorderRadius.circular(4),
              ),
              isDense: true,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.valueText,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: widget.enabled
                      ? const Color(0xFF335C67)
                      : const Color(0xFF9BA9B1),
                ),
              ],
            ),
          ),
        ),
        if (_expanded && widget.enabled) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFBFCBD5)),
              borderRadius: BorderRadius.circular(4),
              color: const Color(0xFFFDFBF7),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: widget.options.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, color: Color(0xFFD7E0E5)),
                itemBuilder: (context, index) {
                  final option = widget.options[index];
                  final isSelected = option.value == widget.currentValue;
                  return ListTile(
                    dense: true,
                    title: Text(option.label),
                    subtitle:
                        option.subtitle == null ? null : Text(option.subtitle!),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: Color(0xFF112A46))
                        : null,
                    onTap: () {
                      widget.onChanged(option.value);
                      setState(() => _expanded = false);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CitySearchField extends StatefulWidget {
  const _CitySearchField({
    required this.label,
    required this.controller,
    required this.onSelected,
    required this.searchCities,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<CitySearchResult> onSelected;
  final Future<List<CitySearchResult>> Function(String query) searchCities;

  @override
  State<_CitySearchField> createState() => _CitySearchFieldState();
}

class _CitySearchFieldState extends State<_CitySearchField> {
  late final FocusNode _focusNode;
  Timer? _debounce;
  int _requestToken = 0;
  bool _isLoading = false;
  List<CitySearchResult> _results = const [];

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()
      ..addListener(() {
        if (_focusNode.hasFocus) {
          _queueSearch(widget.controller.text);
        } else {
          Future<void>.delayed(const Duration(milliseconds: 120), () {
            if (!mounted || _focusNode.hasFocus) {
              return;
            }
            setState(() {
              _results = const [];
              _isLoading = false;
            });
          });
        }
      });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _queueSearch(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    final token = ++_requestToken;
    setState(() {
      _isLoading = true;
    });

    final results = await widget.searchCities(query);
    if (!mounted || token != _requestToken) {
      return;
    }

    setState(() {
      _results = results;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showResults =
        _focusNode.hasFocus && (_isLoading || _results.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: 'Type a city, state, or country',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: _queueSearch,
        ),
        if (showResults) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFBFCBD5)),
              borderRadius: BorderRadius.circular(4),
              color: const Color(0xFFFDFBF7),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Searching cities...',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF335C67),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _results.length,
                      separatorBuilder: (context, index) => const Divider(
                        height: 1,
                        color: Color(0xFFD7E0E5),
                      ),
                      itemBuilder: (context, index) {
                        final option = _results[index];
                        return ListTile(
                          dense: true,
                          title: Text(option.displayName),
                          subtitle: Text(
                            option.population > 0
                                ? 'Population ${option.population}'
                                : option.countryName,
                          ),
                          onTap: () {
                            widget.controller.text = option.displayName;
                            widget.onSelected(option);
                            _focusNode.unfocus();
                            setState(() {
                              _results = const [];
                            });
                          },
                        );
                      },
                    ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.status,
    this.compact = false,
  });

  final _BackendStatus status;
  final bool compact;

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
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 7 : 10,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 8 : 10,
            height: compact ? 8 : 10,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: compact ? 13 : 14,
              color: const Color(0xFF112A46),
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
