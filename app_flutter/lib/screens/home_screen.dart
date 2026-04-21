import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/astronomy_event.dart';
import '../models/astronomy_snapshot.dart';
import '../models/city_search_result.dart';
import '../models/map_label.dart';
import '../models/map_scene.dart';
import '../models/map_shape.dart';
import '../models/measure_result.dart';
import '../models/place_marker.dart';
import '../models/weather_overlay_snapshot.dart';
import '../models/wind_snapshot.dart';
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

enum _WeatherMode { air, ocean, none }

enum _WeatherAnimationMode { wind, currents, waves }

enum _AirOverlayType {
  wind,
  temperature,
  relativeHumidity,
  dewPointTemperature,
  wetBulbTemperature,
  precipitation3h,
  capeSurface,
  totalPrecipitableWater,
  totalCloudWater,
  meanSeaLevelPressure,
  miseryIndex,
  ultravioletIndex,
  instantaneousWindPowerDensity,
  none,
}

enum _OceanOverlayType {
  currents,
  waves,
  htsgw,
  sst,
  ssta,
  baa,
  none,
}

const int _minRouteStops = 2;
const int _maxRouteStops = 6;
const List<int> _gridStepOptions = [5, 10, 15, 20, 30, 45, 60];
const int _healthFailureThreshold = 3;
const double _stateBoundaryZoomThreshold = 3.6;
const double _cityDetailZoomThreshold = 5.6;
const Duration _astronomyPlaybackTick = Duration(milliseconds: 200);
const Duration _cityLabelRefreshDebounce = Duration(milliseconds: 220);
const List<String> _windLevelOptions = <String>[
  'surface',
  '1000',
  '850',
  '700',
  '500',
  '250',
  '70',
  '10',
];
const Map<String, ({double km, double miles})> _windLevelAltitudeByKey =
    <String, ({double km, double miles})>{
  'surface': (km: 0.0, miles: 0.0),
  '1000': (km: 0.11, miles: 0.07),
  '850': (km: 1.46, miles: 0.91),
  '700': (km: 3.01, miles: 1.87),
  '500': (km: 5.57, miles: 3.46),
  '250': (km: 10.36, miles: 6.44),
  '70': (km: 18.71, miles: 11.63),
  '10': (km: 31.06, miles: 19.30),
};

String _playbackPresetLabel(_AstronomyPlaybackPreset preset) {
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

String _playbackSpeedLabel(_AstronomyPlaybackSpeed speed) {
  return switch (speed) {
    _AstronomyPlaybackSpeed.slow => 'Slow',
    _AstronomyPlaybackSpeed.normal => 'Normal',
    _AstronomyPlaybackSpeed.fast => 'Fast',
    _AstronomyPlaybackSpeed.veryFast => 'Very fast',
  };
}

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
const List<String> _astronomyPlanetNames = <String>[
  'Mercury',
  'Venus',
  'Mars',
  'Jupiter',
  'Saturn',
  'Uranus',
  'Neptune',
  'Pluto',
];

String _weatherModeLabel(_WeatherMode mode) {
  return switch (mode) {
    _WeatherMode.air => 'Air',
    _WeatherMode.ocean => 'Ocean',
    _WeatherMode.none => 'None',
  };
}

String _weatherAnimationLabel(_WeatherAnimationMode mode) {
  return switch (mode) {
    _WeatherAnimationMode.wind => 'Wind',
    _WeatherAnimationMode.currents => 'Currents',
    _WeatherAnimationMode.waves => 'Waves',
  };
}

String _weatherAnimationApiValue(_WeatherAnimationMode mode) {
  return switch (mode) {
    _WeatherAnimationMode.wind => 'wind',
    _WeatherAnimationMode.currents => 'currents',
    _WeatherAnimationMode.waves => 'waves',
  };
}

String _airOverlayLabel(_AirOverlayType overlay) {
  return switch (overlay) {
    _AirOverlayType.wind => 'Wind',
    _AirOverlayType.temperature => 'Temperature',
    _AirOverlayType.relativeHumidity => 'Relative Humidity',
    _AirOverlayType.dewPointTemperature => 'Dew Point Temperature',
    _AirOverlayType.wetBulbTemperature => 'Wet Bulb Temperature',
    _AirOverlayType.precipitation3h => '3-Hour Precipitation Accumulation',
    _AirOverlayType.capeSurface =>
      'Convective Available Potential Energy From the Surface',
    _AirOverlayType.totalPrecipitableWater => 'Total Precipitable Water',
    _AirOverlayType.totalCloudWater => 'Total Cloud Water',
    _AirOverlayType.meanSeaLevelPressure => 'Mean Sea Level Pressure',
    _AirOverlayType.miseryIndex => 'Misery Index',
    _AirOverlayType.ultravioletIndex => 'Ultraviolet Index',
    _AirOverlayType.instantaneousWindPowerDensity =>
      'Instantaneous Wind Power Density',
    _AirOverlayType.none => 'None',
  };
}

String? _airOverlayApiValue(_AirOverlayType overlay) {
  return switch (overlay) {
    _AirOverlayType.wind => 'wind',
    _AirOverlayType.temperature => 'temperature',
    _AirOverlayType.relativeHumidity => 'relativeHumidity',
    _AirOverlayType.dewPointTemperature => 'dewPointTemperature',
    _AirOverlayType.wetBulbTemperature => 'wetBulbTemperature',
    _AirOverlayType.precipitation3h => 'precipitation3h',
    _AirOverlayType.capeSurface => 'capeSurface',
    _AirOverlayType.totalPrecipitableWater => 'totalPrecipitableWater',
    _AirOverlayType.totalCloudWater => 'totalCloudWater',
    _AirOverlayType.meanSeaLevelPressure => 'meanSeaLevelPressure',
    _AirOverlayType.miseryIndex => 'miseryIndex',
    _AirOverlayType.ultravioletIndex => 'ultravioletIndex',
    _AirOverlayType.instantaneousWindPowerDensity =>
      'instantaneousWindPowerDensity',
    _AirOverlayType.none => null,
  };
}

String _oceanOverlayLabel(_OceanOverlayType overlay) {
  return switch (overlay) {
    _OceanOverlayType.currents => 'Currents',
    _OceanOverlayType.waves => 'Waves',
    _OceanOverlayType.htsgw => 'Significant Wave Height',
    _OceanOverlayType.sst => 'Sea Surface Temperature',
    _OceanOverlayType.ssta => 'Sea Surface Temperature Anomaly',
    _OceanOverlayType.baa => 'Bleaching Alert Area',
    _OceanOverlayType.none => 'None',
  };
}

String? _oceanOverlayApiValue(_OceanOverlayType overlay) {
  return switch (overlay) {
    _OceanOverlayType.currents => 'currents',
    _OceanOverlayType.waves => 'waves',
    _OceanOverlayType.htsgw => 'htsgw',
    _OceanOverlayType.sst => 'sst',
    _OceanOverlayType.ssta => 'ssta',
    _OceanOverlayType.baa => 'baa',
    _OceanOverlayType.none => null,
  };
}

String _weatherLevelLabel(String level) {
  return level == 'surface' ? 'Surface' : '$level hPa';
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
}) {
  if (_isCelsiusWeatherUnit(unitLabel)) {
    final celsiusText = '${value.toStringAsFixed(1)}°C';
    if (!includeFahrenheitForCelsius) {
      return celsiusText;
    }
    return '$celsiusText / ${_celsiusToFahrenheit(value).toStringAsFixed(1)}°F';
  }
  final trimmedUnit = unitLabel.trim();
  return trimmedUnit.isEmpty
      ? value.toStringAsFixed(1)
      : '${value.toStringAsFixed(1)} $trimmedUnit';
}

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
  bool _showStars = false;
  bool _showConstellations = false;
  bool _showConstellationsFullSky = false;
  bool _weatherOverlayEnabled = false;
  _WeatherMode _weatherMode = _WeatherMode.air;
  _WeatherMode _lastNonNoneWeatherMode = _WeatherMode.air;
  _WeatherAnimationMode _weatherAnimationMode = _WeatherAnimationMode.wind;
  _AirOverlayType _airOverlayType = _AirOverlayType.none;
  _OceanOverlayType _oceanOverlayType = _OceanOverlayType.none;
  String _windLevel = 'surface';
  final Map<String, bool> _planetVisibility = <String, bool>{
    for (final planetName in _astronomyPlanetNames) planetName: false,
  };
  _OuterEdgeMode _outerEdgeMode = _OuterEdgeMode.coastline;
  _AstronomyTimeMode _astronomyTimeMode = _AstronomyTimeMode.current;
  String _astronomyDisplayTimeZone = 'local';
  int _gridStepDegrees = 15;
  bool _isLoading = true;
  String? _error;
  String? _measureError;
  String? _astronomyError;
  String? _astronomyEventError;
  String? _windError;
  String? _weatherOverlayError;
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
  WindSnapshot? _windSnapshot;
  WeatherOverlaySnapshot? _weatherOverlaySnapshot;
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
  bool _isLoadingWind = false;
  bool _isLoadingWeatherOverlay = false;
  int _windRequestSequence = 0;
  int _weatherOverlayRequestSequence = 0;
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
    _trackEvent(
      'app_open',
      properties: <String, dynamic>{
        'path': Uri.base.path.isEmpty ? '/' : Uri.base.path,
      },
    );
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
              : _backendOfflineMessage();
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

  String _backendOfflineMessage() {
    final androidHint = !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android
        ? ' On a physical Android device, run "adb reverse tcp:8002 tcp:8002" or launch with MAYBEFLAT_API_BASE_URL pointed at your LAN backend URL.'
        : '';
    return 'Backend is offline. Start the FastAPI server to load live map data.$androidHint';
  }

  void _trackEvent(
    String name, {
    Map<String, dynamic>? properties,
  }) {
    unawaited(_trackEventSafely(name, properties: properties));
  }

  Future<void> _trackEventSafely(
    String name, {
    Map<String, dynamic>? properties,
  }) async {
    try {
      await _api.trackAnalyticsEvent(
        name: name,
        properties: properties,
      );
    } catch (_) {
      // Analytics should never interrupt the product flow.
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
          _error = _backendOfflineMessage();
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
    if (_shouldShowTimedOverlays &&
        !_isLoadingAstronomy &&
        !_isLoadingWind &&
        !_isLoadingWeatherOverlay) {
      _refreshTimedOverlays();
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
      for (final label in sceneLabels) _labelMergeKey(label),
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

  bool get _showAnyPlanets =>
      _planetVisibility.values.any((isVisible) => isVisible);

  bool get _allPlanetsVisible =>
      _planetVisibility.isNotEmpty &&
      _planetVisibility.values.every((isVisible) => isVisible);

  List<String> get _visiblePlanetNames => _astronomyPlanetNames
      .where((planetName) => _planetVisibility[planetName] ?? false)
      .toList(growable: false);

  bool get _shouldShowAstronomy =>
      _showSunPath ||
      _showMoonPath ||
      _showStars ||
      _showConstellations ||
      _showAnyPlanets;

  _WeatherMode get _overlayWeatherMode => _weatherMode == _WeatherMode.none
      ? _lastNonNoneWeatherMode
      : _weatherMode;

  String get _selectedWeatherAnimationLabel {
    return _weatherMode == _WeatherMode.none
        ? 'None'
        : _weatherAnimationLabel(_weatherAnimationMode);
  }

  String? get _selectedWeatherAnimationApiValue {
    return _weatherMode == _WeatherMode.none
        ? null
        : _weatherAnimationApiValue(_weatherAnimationMode);
  }

  String get _selectedWeatherOverlayLabel {
    return switch (_overlayWeatherMode) {
      _WeatherMode.air => _airOverlayLabel(_airOverlayType),
      _WeatherMode.ocean => _oceanOverlayLabel(_oceanOverlayType),
      _WeatherMode.none => 'None',
    };
  }

  String? get _selectedWeatherOverlayApiValue {
    return switch (_overlayWeatherMode) {
      _WeatherMode.air => _airOverlayApiValue(_airOverlayType),
      _WeatherMode.ocean => _oceanOverlayApiValue(_oceanOverlayType),
      _WeatherMode.none => null,
    };
  }

  bool get _showVectorWeatherPreview =>
      _weatherOverlayEnabled && _weatherMode != _WeatherMode.none;

  bool get _showWindAnimation => _showVectorWeatherPreview;

  bool get _showScalarWeatherOverlay =>
      _weatherOverlayEnabled && _selectedWeatherOverlayApiValue != null;

  bool get _showWindScalarOverlay =>
      _showScalarWeatherOverlay &&
      _overlayWeatherMode == _WeatherMode.air &&
      _airOverlayType == _AirOverlayType.wind;

  bool get _shouldLoadWindSnapshot => _showVectorWeatherPreview;

  bool get _shouldLoadWeatherOverlaySnapshot => _showScalarWeatherOverlay;

  bool get _shouldShowTimedOverlays =>
      _shouldShowAstronomy ||
      _shouldLoadWindSnapshot ||
      _shouldLoadWeatherOverlaySnapshot;

  Map<String, dynamic> _astronomyVisibilityProperties() {
    final visiblePlanets = _visiblePlanetNames;
    return <String, dynamic>{
      'sun_path': _showSunPath,
      'moon_path': _showMoonPath,
      'stars': _showStars,
      'constellations': _showConstellations,
      'constellations_full_sky': _showConstellationsFullSky,
      'visible_planet_count': visiblePlanets.length,
      'visible_planets': visiblePlanets,
    };
  }

  void _finalizeAstronomyVisibilityChange(bool wasShowingAstronomy) {
    final wasShowingTimedOverlays =
        wasShowingAstronomy || _shouldLoadWindSnapshot;
    if (!_shouldShowTimedOverlays) {
      _stopAstronomyPlayback();
    }
    if (!wasShowingAstronomy && _shouldShowAstronomy) {
      _trackEvent(
        'astronomy_enabled',
        properties: _astronomyVisibilityProperties(),
      );
    }
    _syncAstronomyTimer();
    if (_shouldShowTimedOverlays &&
        wasShowingTimedOverlays != _shouldShowTimedOverlays) {
      _trackEvent(
        'timed_overlay_enabled',
        properties: <String, dynamic>{
          'astronomy': _shouldShowAstronomy,
          'wind': _shouldLoadWindSnapshot,
        },
      );
    }
    if (_shouldShowTimedOverlays) {
      _refreshTimedOverlays();
    }
  }

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

  void _resetAstronomyPlaybackDefaults({DateTime? referenceTime}) {
    final baseTime = referenceTime ?? DateTime.now();
    final duration = _astronomyPlaybackPresetDuration(
      _AstronomyPlaybackPreset.oneDay,
    );
    final halfDuration = Duration(
      milliseconds: math.max(1, duration.inMilliseconds ~/ 2),
    );
    _astronomyPlaybackPreset = _AstronomyPlaybackPreset.oneDay;
    _astronomyPlaybackSpeed = _AstronomyPlaybackSpeed.normal;
    _astronomyPlaybackStart = baseTime.subtract(halfDuration);
    _astronomyPlaybackEnd = _astronomyPlaybackStart.add(duration);
    _astronomyCustomTime = baseTime;
    _syncAstronomyPlaybackTime();
  }

  DateTime _astronomyTimestampUtc() {
    return switch (_astronomyTimeMode) {
      _AstronomyTimeMode.current => DateTime.now().toUtc(),
      _AstronomyTimeMode.custom => _astronomyCustomTime.toUtc(),
    };
  }

  void _syncAstronomyTimer() {
    _astronomyTimer?.cancel();
    if (!_shouldShowTimedOverlays ||
        _astronomyTimeMode != _AstronomyTimeMode.current) {
      return;
    }
    _astronomyTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshTimedOverlays(),
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
    _astronomyCustomTime =
        startUtc.add(Duration(milliseconds: elapsedMilliseconds)).toLocal();
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
    if (_shouldShowTimedOverlays) {
      _refreshTimedOverlays();
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
    if (_shouldShowTimedOverlays) {
      await _refreshTimedOverlays();
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
    if (_shouldShowTimedOverlays) {
      await _refreshTimedOverlays();
    }
  }

  void _toggleAstronomyPlayback() {
    if (_isAstronomyPlaying) {
      _stopAstronomyPlayback();
      return;
    }
    if (_backendStatus == _BackendStatus.offline || !_shouldShowTimedOverlays) {
      setState(() {
        _astronomyError =
            'Enable astronomy, a weather overlay, or an Air/Ocean animation and keep the backend online to use playback.';
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
        if (!mounted ||
            _isLoadingAstronomy ||
            _isLoadingWind ||
            _isLoadingWeatherOverlay) {
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
        await _refreshTimedOverlays(quiet: true);
        if (!mounted || _astronomyPlaybackProgress >= 1) {
          _stopAstronomyPlayback();
        }
      },
    );
  }

  Future<void> _refreshTimedOverlays({
    bool quiet = false,
    DateTime? timestampUtcOverride,
  }) async {
    final tasks = <Future<void>>[];
    if (_shouldShowAstronomy) {
      tasks.add(
        _loadAstronomy(
          quiet: quiet,
          timestampUtcOverride: timestampUtcOverride,
        ),
      );
    }
    if (_shouldLoadWindSnapshot) {
      tasks.add(
        _loadWind(
          quiet: quiet,
          timestampUtcOverride: timestampUtcOverride,
        ),
      );
    }
    if (_shouldLoadWeatherOverlaySnapshot) {
      tasks.add(
        _loadWeatherOverlay(
          quiet: quiet,
          timestampUtcOverride: timestampUtcOverride,
        ),
      );
    }
    if (tasks.isEmpty) {
      return;
    }
    await Future.wait(tasks);
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
            'Backend must be online to load the astronomy overlay.';
      });
      return;
    }

    final requestSequence = ++_astronomyRequestSequence;
    final effectiveTimestampUtc =
        (timestampUtcOverride ?? _astronomyTimestampUtc()).toUtc();

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

  Future<void> _loadWind({
    bool quiet = false,
    DateTime? timestampUtcOverride,
  }) async {
    if (!_shouldLoadWindSnapshot) {
      if (!mounted) {
        return;
      }
      setState(() {
        _windSnapshot = null;
        _windError = null;
        _isLoadingWind = false;
      });
      return;
    }
    if (_backendStatus == _BackendStatus.offline) {
      if (!mounted) {
        return;
      }
      setState(() {
        _windSnapshot = null;
        _windError =
            'Backend must be online to load the ${_selectedWeatherAnimationLabel.toLowerCase()} animation.';
      });
      return;
    }

    final requestSequence = ++_windRequestSequence;
    final effectiveTimestampUtc =
        (timestampUtcOverride ?? _astronomyTimestampUtc()).toUtc();

    if (quiet) {
      _isLoadingWind = true;
    } else if (mounted) {
      setState(() {
        _isLoadingWind = true;
        _windError = null;
      });
    }

    try {
      final animationMode = _selectedWeatherAnimationApiValue;
      if (animationMode == null) {
        throw StateError('No active weather animation mode.');
      }
      final snapshot = await _api.loadWeatherAnimationSnapshot(
        mode: animationMode,
        timestampUtc: effectiveTimestampUtc,
        level: _windLevel,
      );
      if (!mounted || requestSequence != _windRequestSequence) {
        return;
      }
      setState(() {
        _windSnapshot = snapshot;
        _windError = null;
      });
    } catch (_) {
      if (!mounted || requestSequence != _windRequestSequence) {
        return;
      }
      setState(() {
        _windSnapshot = null;
        _windError =
            'Could not load the ${_selectedWeatherAnimationLabel.toLowerCase()} animation from the backend.';
      });
      if (_isAstronomyPlaying) {
        _stopAstronomyPlayback();
      }
    } finally {
      if (quiet) {
        if (requestSequence == _windRequestSequence) {
          _isLoadingWind = false;
        }
      } else if (mounted) {
        if (requestSequence == _windRequestSequence) {
          setState(() {
            _isLoadingWind = false;
          });
        }
      }
    }
  }

  Future<void> _loadWeatherOverlay({
    bool quiet = false,
    DateTime? timestampUtcOverride,
  }) async {
    if (!_shouldLoadWeatherOverlaySnapshot) {
      if (!mounted) {
        return;
      }
      setState(() {
        _weatherOverlaySnapshot = null;
        _weatherOverlayError = null;
        _isLoadingWeatherOverlay = false;
      });
      return;
    }
    if (_backendStatus == _BackendStatus.offline) {
      if (!mounted) {
        return;
      }
      setState(() {
        _weatherOverlaySnapshot = null;
        _weatherOverlayError =
            'Backend must be online to load the ${_selectedWeatherOverlayLabel.toLowerCase()} overlay.';
      });
      return;
    }

    final overlay = _selectedWeatherOverlayApiValue;
    if (overlay == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _weatherOverlaySnapshot = null;
        _weatherOverlayError = null;
        _isLoadingWeatherOverlay = false;
      });
      return;
    }

    final requestSequence = ++_weatherOverlayRequestSequence;
    final effectiveTimestampUtc =
        (timestampUtcOverride ?? _astronomyTimestampUtc()).toUtc();

    if (quiet) {
      _isLoadingWeatherOverlay = true;
    } else if (mounted) {
      setState(() {
        _isLoadingWeatherOverlay = true;
        _weatherOverlayError = null;
      });
    }

    try {
      final snapshot = _overlayWeatherMode == _WeatherMode.ocean
          ? await _api.loadOceanOverlaySnapshot(
              overlay: overlay,
              timestampUtc: effectiveTimestampUtc,
            )
          : await _api.loadWeatherOverlaySnapshot(
              overlay: overlay,
              timestampUtc: effectiveTimestampUtc,
              level: _windLevel,
            );
      if (!mounted || requestSequence != _weatherOverlayRequestSequence) {
        return;
      }
      setState(() {
        _weatherOverlaySnapshot = snapshot;
        _weatherOverlayError = null;
      });
    } catch (_) {
      if (!mounted || requestSequence != _weatherOverlayRequestSequence) {
        return;
      }
      setState(() {
        _weatherOverlaySnapshot = null;
        _weatherOverlayError =
            'Could not load the ${_selectedWeatherOverlayLabel.toLowerCase()} overlay from the backend.';
      });
      if (_isAstronomyPlaying) {
        _stopAstronomyPlayback();
      }
    } finally {
      if (quiet) {
        if (requestSequence == _weatherOverlayRequestSequence) {
          _isLoadingWeatherOverlay = false;
        }
      } else if (mounted) {
        if (requestSequence == _weatherOverlayRequestSequence) {
          setState(() {
            _isLoadingWeatherOverlay = false;
          });
        }
      }
    }
  }

  void _setAstronomyToggle({
    bool? showSunPath,
    bool? showMoonPath,
    bool? showStars,
    bool? showConstellations,
    bool? showConstellationsFullSky,
  }) {
    final wasShowingAstronomy = _shouldShowAstronomy;
    setState(() {
      if (showSunPath != null) {
        _showSunPath = showSunPath;
      }
      if (showMoonPath != null) {
        _showMoonPath = showMoonPath;
      }
      if (showStars != null) {
        _showStars = showStars;
      }
      if (showConstellations != null) {
        _showConstellations = showConstellations;
      }
      if (showConstellationsFullSky != null) {
        _showConstellationsFullSky = showConstellationsFullSky;
      }
      if (!_shouldShowAstronomy) {
        _astronomySnapshot = null;
        _astronomyError = null;
      }
    });
    _finalizeAstronomyVisibilityChange(wasShowingAstronomy);
  }

  void _setWeatherMode(_WeatherMode? mode) {
    if (mode == null || _weatherMode == mode) {
      return;
    }

    final wasShowingTimedOverlays = _shouldShowTimedOverlays;
    setState(() {
      _weatherMode = mode;
      if (mode != _WeatherMode.none) {
        _lastNonNoneWeatherMode = mode;
      }
      if (!_shouldLoadWindSnapshot) {
        _windSnapshot = null;
        _windError = null;
      }
      if (!_shouldLoadWeatherOverlaySnapshot) {
        _weatherOverlaySnapshot = null;
        _weatherOverlayError = null;
      }
    });
    _syncAstronomyTimer();
    if (_shouldShowTimedOverlays) {
      _refreshTimedOverlays();
    } else if (wasShowingTimedOverlays) {
      _stopAstronomyPlayback();
    }
  }

  void _setWeatherOverlayEnabled(bool isEnabled) {
    if (_weatherOverlayEnabled == isEnabled) {
      return;
    }

    final wasShowingTimedOverlays = _shouldShowTimedOverlays;
    setState(() {
      _weatherOverlayEnabled = isEnabled;
      if (!_shouldLoadWindSnapshot) {
        _windSnapshot = null;
        _windError = null;
      }
      if (!_shouldLoadWeatherOverlaySnapshot) {
        _weatherOverlaySnapshot = null;
        _weatherOverlayError = null;
      }
    });
    if (!wasShowingTimedOverlays && _shouldShowTimedOverlays) {
      _trackEvent(
        'timed_overlay_enabled',
        properties: <String, dynamic>{
          'astronomy': _shouldShowAstronomy,
          'wind': _shouldLoadWindSnapshot,
        },
      );
    }
    _trackEvent(
      'weather_overlay_toggle',
      properties: <String, dynamic>{
        'enabled': isEnabled,
      },
    );
    _syncAstronomyTimer();
    if (_shouldShowTimedOverlays) {
      _refreshTimedOverlays();
    } else {
      _stopAstronomyPlayback();
    }
  }

  void _setWeatherAnimationMode(_WeatherAnimationMode? mode) {
    if (mode == null || _weatherAnimationMode == mode) {
      return;
    }

    final wasShowingTimedOverlays = _shouldShowTimedOverlays;
    setState(() {
      _weatherAnimationMode = mode;
      if (!_shouldLoadWindSnapshot) {
        _windSnapshot = null;
        _windError = null;
      }
      if (!_shouldLoadWeatherOverlaySnapshot) {
        _weatherOverlaySnapshot = null;
        _weatherOverlayError = null;
      }
    });
    if (!wasShowingTimedOverlays && _shouldShowTimedOverlays) {
      _trackEvent(
        'timed_overlay_enabled',
        properties: <String, dynamic>{
          'astronomy': _shouldShowAstronomy,
          'wind': _shouldLoadWindSnapshot,
        },
      );
    }
    _trackEvent(
      'weather_animation_changed',
      properties: <String, dynamic>{
        'animate': _weatherAnimationLabel(mode).toLowerCase(),
      },
    );
    _syncAstronomyTimer();
    if (_shouldShowTimedOverlays) {
      _refreshTimedOverlays();
    } else {
      _stopAstronomyPlayback();
    }
  }

  void _setAirOverlayType(_AirOverlayType? overlay) {
    if (overlay == null || _airOverlayType == overlay) {
      return;
    }

    final wasShowingTimedOverlays = _shouldShowTimedOverlays;
    setState(() {
      _airOverlayType = overlay;
      _weatherOverlaySnapshot = null;
      _weatherOverlayError = null;
      if (!_shouldLoadWindSnapshot) {
        _windSnapshot = null;
        _windError = null;
      }
      if (!_shouldLoadWeatherOverlaySnapshot) {
        _weatherOverlaySnapshot = null;
        _weatherOverlayError = null;
      }
    });
    if (!wasShowingTimedOverlays && _shouldShowTimedOverlays) {
      _trackEvent(
        'timed_overlay_enabled',
        properties: <String, dynamic>{
          'astronomy': _shouldShowAstronomy,
          'wind': _shouldLoadWindSnapshot,
        },
      );
    }
    _trackEvent(
      'air_overlay_changed',
      properties: <String, dynamic>{
        'overlay': _airOverlayType.name,
      },
    );
    _syncAstronomyTimer();
    if (_shouldShowTimedOverlays) {
      _refreshTimedOverlays();
    } else {
      _stopAstronomyPlayback();
    }
  }

  void _setOceanOverlayType(_OceanOverlayType? overlay) {
    if (overlay == null || _oceanOverlayType == overlay) {
      return;
    }

    final wasShowingTimedOverlays = _shouldShowTimedOverlays;
    setState(() {
      _oceanOverlayType = overlay;
      _weatherOverlaySnapshot = null;
      _weatherOverlayError = null;
      if (!_shouldLoadWindSnapshot) {
        _windSnapshot = null;
        _windError = null;
      }
      if (!_shouldLoadWeatherOverlaySnapshot) {
        _weatherOverlaySnapshot = null;
        _weatherOverlayError = null;
      }
    });
    if (!wasShowingTimedOverlays && _shouldShowTimedOverlays) {
      _trackEvent(
        'timed_overlay_enabled',
        properties: <String, dynamic>{
          'astronomy': _shouldShowAstronomy,
          'wind': _shouldLoadWindSnapshot,
        },
      );
    }
    _trackEvent(
      'ocean_overlay_changed',
      properties: <String, dynamic>{
        'overlay': _oceanOverlayType.name,
      },
    );
    _syncAstronomyTimer();
    if (_shouldShowTimedOverlays) {
      _refreshTimedOverlays();
    } else {
      _stopAstronomyPlayback();
    }
  }

  void _setWindLevel(String? level) {
    if (level == null || _windLevel == level) {
      return;
    }

    setState(() {
      _windLevel = level;
      if (_shouldLoadWeatherOverlaySnapshot) {
        _weatherOverlaySnapshot = null;
        _weatherOverlayError = null;
      }
    });
    _trackEvent(
      'wind_level_changed',
      properties: <String, dynamic>{
        'level': level,
      },
    );
    if (_shouldLoadWindSnapshot && _weatherMode == _WeatherMode.air) {
      _loadWind();
    }
    if (_shouldLoadWeatherOverlaySnapshot &&
        _overlayWeatherMode == _WeatherMode.air) {
      _loadWeatherOverlay();
    } else {
      setState(() {
        _weatherOverlaySnapshot = null;
        _weatherOverlayError = null;
      });
    }
  }

  void _setPlanetVisibility(String planetName, bool isVisible) {
    if ((_planetVisibility[planetName] ?? false) == isVisible) {
      return;
    }
    final wasShowingAstronomy = _shouldShowAstronomy;
    setState(() {
      _planetVisibility[planetName] = isVisible;
      if (!_shouldShowAstronomy) {
        _astronomySnapshot = null;
        _astronomyError = null;
      }
    });
    _trackEvent(
      'astronomy_planet_toggle',
      properties: <String, dynamic>{
        'planet': planetName.toLowerCase(),
        'enabled': isVisible,
        'visible_planet_count': _visiblePlanetNames.length,
      },
    );
    _finalizeAstronomyVisibilityChange(wasShowingAstronomy);
  }

  void _setAllPlanetsVisibility(bool isVisible) {
    final hasChange = _astronomyPlanetNames.any(
      (planetName) => (_planetVisibility[planetName] ?? false) != isVisible,
    );
    if (!hasChange) {
      return;
    }
    final wasShowingAstronomy = _shouldShowAstronomy;
    setState(() {
      for (final planetName in _astronomyPlanetNames) {
        _planetVisibility[planetName] = isVisible;
      }
      if (!_shouldShowAstronomy) {
        _astronomySnapshot = null;
        _astronomyError = null;
      }
    });
    _trackEvent(
      'astronomy_planet_toggle',
      properties: <String, dynamic>{
        'planet': 'all',
        'enabled': isVisible,
        'visible_planet_count': _visiblePlanetNames.length,
      },
    );
    _finalizeAstronomyVisibilityChange(wasShowingAstronomy);
  }

  void _setAstronomyTimeMode(_AstronomyTimeMode mode) {
    final switchingToCurrent = mode == _AstronomyTimeMode.current;
    _astronomyPlaybackTimer?.cancel();
    _astronomyPlaybackTimer = null;
    setState(() {
      _astronomyTimeMode = mode;
      _isAstronomyPlaying = false;
      if (switchingToCurrent) {
        _resetAstronomyPlaybackDefaults(referenceTime: DateTime.now());
      } else {
        _syncAstronomyPlaybackTime();
        _astronomyCustomTime = _astronomyPlaybackCurrentTime();
      }
    });
    _syncAstronomyTimer();
    if (_shouldShowTimedOverlays) {
      _refreshTimedOverlays();
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
    if (_shouldShowTimedOverlays) {
      _refreshTimedOverlays();
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
    if (observer != null) {
      _trackEvent(
        'city_search_selected',
        properties: <String, dynamic>{
          'feature': 'astronomy_observer',
          'country': observer.countryCode,
          'population': observer.population,
        },
      );
      _trackEvent(
        'astronomy_observer_selected',
        properties: <String, dynamic>{
          'country': observer.countryCode,
          'population': observer.population,
        },
      );
    }
    if (_shouldShowTimedOverlays) {
      _refreshTimedOverlays();
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

  String _windAltitudeExplanation(String level) {
    final altitude = _windLevelAltitudeByKey[level];
    if (altitude == null) {
      return 'Approx altitude unavailable.';
    }
    return 'Approx altitude: ${altitude.km.toStringAsFixed(2)} km / ${altitude.miles.toStringAsFixed(2)} mi above sea level.';
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
    _trackEvent(
      'astronomy_event_selected',
      properties: <String, dynamic>{
        'event_type': event.eventType,
        'subtype': event.subtype,
      },
    );
    await _refreshTimedOverlays(timestampUtcOverride: event.timestampUtc);
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
      _trackEvent(
        'city_search_selected',
        properties: <String, dynamic>{
          'feature': 'route_stop',
          'stop_index': stopIndex + 1,
          'country': entry.countryCode,
          'population': entry.population,
        },
      );
      _trackEvent(
        'route_stop_added',
        properties: <String, dynamic>{
          'source': 'city_search',
          'stop_index': stopIndex + 1,
        },
      );

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
      _trackEvent(
        'route_stop_added',
        properties: <String, dynamic>{
          'source': 'map_pick',
          'stop_index': stopIndex + 1,
        },
      );

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
      _trackEvent(
        'route_measured',
        properties: <String, dynamic>{
          'stop_count': filledStops.length,
          'leg_count': results.length,
        },
      );
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
            : _error ??
                _measureError ??
                _astronomyError ??
                _windError ??
                _weatherOverlayError;
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
          showStars: _showStars,
          showConstellations: _showConstellations,
          showConstellationsFullSky: _showConstellationsFullSky,
          weatherOverlayEnabled: _weatherOverlayEnabled,
          weatherMode: _weatherMode,
          lastNonNoneWeatherMode: _lastNonNoneWeatherMode,
          weatherAnimationMode: _weatherAnimationMode,
          airOverlayType: _airOverlayType,
          oceanOverlayType: _oceanOverlayType,
          windLevel: _windLevel,
          allPlanetsVisible: _allPlanetsVisible,
          planetVisibility: _planetVisibility,
          astronomyTimeMode: _astronomyTimeMode,
          astronomyDisplayTimeZone: _astronomyDisplayTimeZone,
          astronomyDisplayTimeZoneOptions: _astronomyDisplayTimeZoneOptions,
          isLoading: _isLoading,
          isLoadingAstronomy: _isLoadingAstronomy,
          isLoadingWind: _isLoadingWind,
          isLoadingWeatherOverlay: _isLoadingWeatherOverlay,
          isMeasuring: _isMeasuring,
          error: _error,
          measureError: _measureError,
          astronomyError: _astronomyError,
          windError: _windError,
          weatherOverlayError: _weatherOverlayError,
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
          windSnapshot: _windSnapshot,
          weatherOverlaySnapshot: _weatherOverlaySnapshot,
          windAltitudeExplanation: _windAltitudeExplanation(
            _windSnapshot?.level ?? _windLevel,
          ),
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
          weatherOverlaySnapshotTimeLabel: _weatherOverlaySnapshot == null
              ? null
              : _formatAstronomyTimeLabel(
                  _weatherOverlaySnapshot!.timestampUtc,
                ),
          windSnapshotTimeLabel: _windSnapshot == null
              ? null
              : _formatAstronomyTimeLabel(_windSnapshot!.timestampUtc),
          astronomyPlaybackStartLabel: _formatAstronomyTimeLabel(
            _astronomyPlaybackStart.toUtc(),
          ),
          astronomyPlaybackEndLabel: _formatAstronomyTimeLabel(
            _astronomyPlaybackEnd.toUtc(),
          ),
          astronomyPlaybackCurrentLabel: _formatAstronomyTimeLabel(
            (_astronomyTimeMode == _AstronomyTimeMode.current
                    ? DateTime.now()
                    : _astronomyCustomTime)
                .toUtc(),
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
          onShowStarsChanged: (value) => _setAstronomyToggle(showStars: value),
          onShowConstellationsChanged: (value) =>
              _setAstronomyToggle(showConstellations: value),
          onShowConstellationsFullSkyChanged: (value) => _setAstronomyToggle(
            showConstellationsFullSky: value,
          ),
          onWeatherOverlayEnabledChanged: _setWeatherOverlayEnabled,
          onWeatherModeChanged: _setWeatherMode,
          onWeatherAnimationModeChanged: _setWeatherAnimationMode,
          onAirOverlayTypeChanged: _setAirOverlayType,
          onOceanOverlayTypeChanged: _setOceanOverlayType,
          onWindLevelChanged: _setWindLevel,
          onShowAllPlanetsChanged: _setAllPlanetsVisibility,
          onShowPlanetChanged: _setPlanetVisibility,
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
            _trackEvent(
              'scene_reload_requested',
              properties: <String, dynamic>{
                'detail': _currentSceneDetail(),
              },
            );
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
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFFDCECEF),
                        Color(0xFFA8D1D3),
                        Color(0xFF6FA9B4),
                      ],
                      stops: [0.0, 0.42, 1.0],
                    ),
                  ),
                ),
              ),
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
                        showStars: _showStars,
                        showConstellations: _showConstellations,
                        showConstellationsFullSky: _showConstellationsFullSky,
                        windSnapshot: _windSnapshot,
                        showWindAnimation: _showWindAnimation,
                        showWindOverlay: _showWindScalarOverlay &&
                            _weatherOverlaySnapshot == null,
                        weatherAnimationLabel: _selectedWeatherAnimationLabel,
                        weatherOverlaySnapshot: _weatherOverlaySnapshot,
                        showWeatherOverlay: _showScalarWeatherOverlay,
                        animateWind: _isAstronomyPlaying,
                        visiblePlanetNames: _visiblePlanetNames,
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
                      onPressed: () {
                        final nextValue = !_showSettingsPanel;
                        setState(() {
                          _showSettingsPanel = nextValue;
                        });
                        if (nextValue) {
                          _trackEvent('settings_opened');
                        }
                      },
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
    required this.showStars,
    required this.showConstellations,
    required this.showConstellationsFullSky,
    required this.weatherOverlayEnabled,
    required this.weatherMode,
    required this.lastNonNoneWeatherMode,
    required this.weatherAnimationMode,
    required this.airOverlayType,
    required this.oceanOverlayType,
    required this.windLevel,
    required this.allPlanetsVisible,
    required this.planetVisibility,
    required this.astronomyTimeMode,
    required this.astronomyDisplayTimeZone,
    required this.astronomyDisplayTimeZoneOptions,
    required this.isLoading,
    required this.isLoadingAstronomy,
    required this.isLoadingWind,
    required this.isLoadingWeatherOverlay,
    required this.isMeasuring,
    required this.error,
    required this.measureError,
    required this.astronomyError,
    required this.windError,
    required this.weatherOverlayError,
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
    required this.windSnapshot,
    required this.weatherOverlaySnapshot,
    required this.windAltitudeExplanation,
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
    required this.weatherOverlaySnapshotTimeLabel,
    required this.windSnapshotTimeLabel,
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
    required this.onShowStarsChanged,
    required this.onShowConstellationsChanged,
    required this.onShowConstellationsFullSkyChanged,
    required this.onWeatherOverlayEnabledChanged,
    required this.onWeatherModeChanged,
    required this.onWeatherAnimationModeChanged,
    required this.onAirOverlayTypeChanged,
    required this.onOceanOverlayTypeChanged,
    required this.onWindLevelChanged,
    required this.onShowAllPlanetsChanged,
    required this.onShowPlanetChanged,
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
  final bool showStars;
  final bool showConstellations;
  final bool showConstellationsFullSky;
  final bool weatherOverlayEnabled;
  final _WeatherMode weatherMode;
  final _WeatherMode lastNonNoneWeatherMode;
  final _WeatherAnimationMode weatherAnimationMode;
  final _AirOverlayType airOverlayType;
  final _OceanOverlayType oceanOverlayType;
  final String windLevel;
  final bool allPlanetsVisible;
  final Map<String, bool> planetVisibility;
  final _AstronomyTimeMode astronomyTimeMode;
  final String astronomyDisplayTimeZone;
  final List<_ChoiceItem<String>> astronomyDisplayTimeZoneOptions;
  final bool isLoading;
  final bool isLoadingAstronomy;
  final bool isLoadingWind;
  final bool isLoadingWeatherOverlay;
  final bool isMeasuring;
  final String? error;
  final String? measureError;
  final String? astronomyError;
  final String? windError;
  final String? weatherOverlayError;
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
  final WindSnapshot? windSnapshot;
  final WeatherOverlaySnapshot? weatherOverlaySnapshot;
  final String windAltitudeExplanation;
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
  final String? weatherOverlaySnapshotTimeLabel;
  final String? windSnapshotTimeLabel;
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
  final ValueChanged<bool> onShowStarsChanged;
  final ValueChanged<bool> onShowConstellationsChanged;
  final ValueChanged<bool> onShowConstellationsFullSkyChanged;
  final ValueChanged<bool> onWeatherOverlayEnabledChanged;
  final ValueChanged<_WeatherMode?> onWeatherModeChanged;
  final ValueChanged<_WeatherAnimationMode?> onWeatherAnimationModeChanged;
  final ValueChanged<_AirOverlayType?> onAirOverlayTypeChanged;
  final ValueChanged<_OceanOverlayType?> onOceanOverlayTypeChanged;
  final ValueChanged<String?> onWindLevelChanged;
  final ValueChanged<bool> onShowAllPlanetsChanged;
  final void Function(String planetName, bool isVisible) onShowPlanetChanged;
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
    final overlayMode =
        weatherMode == _WeatherMode.none ? lastNonNoneWeatherMode : weatherMode;
    final selectedAnimationLabel = switch (weatherMode) {
      _WeatherMode.air || _WeatherMode.ocean =>
        _weatherAnimationLabel(weatherAnimationMode),
      _WeatherMode.none => 'None',
    };
    final selectedOverlayLabel = switch (overlayMode) {
      _WeatherMode.air => _airOverlayLabel(airOverlayType),
      _WeatherMode.ocean => _oceanOverlayLabel(oceanOverlayType),
      _WeatherMode.none => 'None',
    };
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
                title: 'Weather Overlay',
                subtitle:
                    'Weather starts off and can be enabled when you want a map overlay',
                initiallyExpanded: false,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: weatherOverlayEnabled,
                    title: const Text('Enable weather overlay'),
                    subtitle: const Text(
                      'Starts off by default. Turn this on before loading air or ocean layers.',
                    ),
                    onChanged: onWeatherOverlayEnabledChanged,
                  ),
                  const SizedBox(height: 12),
                  _SelectionField(
                    labelText: 'Mode',
                    valueText: _weatherModeLabel(weatherMode),
                    currentValue: weatherMode,
                    onChanged: onWeatherModeChanged,
                    options: const [
                      _ChoiceItem(
                        value: _WeatherMode.none,
                        label: 'None',
                        subtitle:
                            'Disable animation and keep overlay-only weather.',
                      ),
                      _ChoiceItem(
                        value: _WeatherMode.air,
                        label: 'Air',
                        subtitle: 'Wind and atmospheric scalar fields.',
                      ),
                      _ChoiceItem(
                        value: _WeatherMode.ocean,
                        label: 'Ocean',
                        subtitle: 'Currents, waves, and ocean surface fields.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SelectionField(
                    labelText: 'Animate',
                    valueText: weatherMode == _WeatherMode.none
                        ? 'None'
                        : _weatherAnimationLabel(weatherAnimationMode),
                    currentValue: weatherAnimationMode,
                    enabled: weatherOverlayEnabled &&
                        weatherMode != _WeatherMode.none,
                    onChanged: onWeatherAnimationModeChanged,
                    options: const [
                      _ChoiceItem(
                        value: _WeatherAnimationMode.wind,
                        label: 'Wind',
                        subtitle: 'Available now.',
                      ),
                      _ChoiceItem(
                        value: _WeatherAnimationMode.currents,
                        label: 'Currents',
                        subtitle: 'Available now.',
                      ),
                      _ChoiceItem(
                        value: _WeatherAnimationMode.waves,
                        label: 'Waves',
                        subtitle: 'Available now.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SelectionField(
                    labelText: 'Height',
                    valueText:
                        windLevel == 'surface' ? 'Surface' : '$windLevel hPa',
                    currentValue: windLevel,
                    enabled: weatherOverlayEnabled &&
                        (overlayMode == _WeatherMode.air ||
                            weatherAnimationMode == _WeatherAnimationMode.wind),
                    onChanged: onWindLevelChanged,
                    options: [
                      for (final level in _windLevelOptions)
                        _ChoiceItem(
                          value: level,
                          label: level == 'surface' ? 'Surface' : '$level hPa',
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (overlayMode == _WeatherMode.air)
                    _SelectionField(
                      labelText: 'Overlay',
                      valueText: _airOverlayLabel(airOverlayType),
                      currentValue: airOverlayType,
                      enabled: weatherOverlayEnabled,
                      onChanged: onAirOverlayTypeChanged,
                      options: const [
                        _ChoiceItem(
                          value: _AirOverlayType.wind,
                          label: 'Wind',
                        ),
                        _ChoiceItem(
                          value: _AirOverlayType.temperature,
                          label: 'Temperature',
                        ),
                        _ChoiceItem(
                          value: _AirOverlayType.relativeHumidity,
                          label: 'Relative Humidity',
                        ),
                        _ChoiceItem(
                          value: _AirOverlayType.dewPointTemperature,
                          label: 'Dew Point Temperature',
                        ),
                        _ChoiceItem(
                          value: _AirOverlayType.wetBulbTemperature,
                          label: 'Wet Bulb Temperature',
                        ),
                        _ChoiceItem(
                          value: _AirOverlayType.precipitation3h,
                          label: '3-Hour Precipitation Accumulation',
                        ),
                        _ChoiceItem(
                          value: _AirOverlayType.capeSurface,
                          label:
                              'Convective Available Potential Energy From the Surface',
                        ),
                        _ChoiceItem(
                          value: _AirOverlayType.totalPrecipitableWater,
                          label: 'Total Precipitable Water',
                        ),
                        _ChoiceItem(
                          value: _AirOverlayType.totalCloudWater,
                          label: 'Total Cloud Water',
                        ),
                        _ChoiceItem(
                          value: _AirOverlayType.meanSeaLevelPressure,
                          label: 'Mean Sea Level Pressure',
                        ),
                        _ChoiceItem(
                          value: _AirOverlayType.miseryIndex,
                          label: 'Misery Index',
                        ),
                        _ChoiceItem(
                          value: _AirOverlayType.ultravioletIndex,
                          label: 'Ultraviolet Index',
                        ),
                        _ChoiceItem(
                          value: _AirOverlayType.instantaneousWindPowerDensity,
                          label: 'Instantaneous Wind Power Density',
                        ),
                        _ChoiceItem(
                          value: _AirOverlayType.none,
                          label: 'None',
                          subtitle: 'Hide scalar coloring.',
                        ),
                      ],
                    )
                  else
                    _SelectionField(
                      labelText: 'Overlay',
                      valueText: _oceanOverlayLabel(oceanOverlayType),
                      currentValue: oceanOverlayType,
                      enabled: weatherOverlayEnabled,
                      onChanged: onOceanOverlayTypeChanged,
                      options: const [
                        _ChoiceItem(
                          value: _OceanOverlayType.currents,
                          label: 'Currents',
                        ),
                        _ChoiceItem(
                          value: _OceanOverlayType.waves,
                          label: 'Waves',
                        ),
                        _ChoiceItem(
                          value: _OceanOverlayType.htsgw,
                          label: 'Significant Wave Height',
                        ),
                        _ChoiceItem(
                          value: _OceanOverlayType.sst,
                          label: 'Sea Surface Temperature',
                        ),
                        _ChoiceItem(
                          value: _OceanOverlayType.ssta,
                          label: 'Sea Surface Temperature Anomaly',
                        ),
                        _ChoiceItem(
                          value: _OceanOverlayType.baa,
                          label: 'Bleaching Alert Area',
                        ),
                        _ChoiceItem(
                          value: _OceanOverlayType.none,
                          label: 'None',
                          subtitle: 'Hide scalar coloring.',
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Text(
                    !weatherOverlayEnabled
                        ? 'Weather is turned off by default. Turn it on to animate air or ocean fields and color the map by the selected scale.'
                        : weatherMode == _WeatherMode.none &&
                                selectedOverlayLabel == 'None'
                            ? 'Weather is enabled, but both animation and scalar coloring are off.'
                            : weatherMode == _WeatherMode.none
                                ? '$selectedOverlayLabel colors the map by scale without animation.'
                                : selectedOverlayLabel == 'None'
                                    ? '$selectedAnimationLabel animation stays on as the live preview. Overlay coloring is hidden while None is selected.'
                                    : '$selectedOverlayLabel now uses a backend scalar field to color the map by scale while ${selectedAnimationLabel.toLowerCase()} continues to drive the animation preview.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF335C67),
                      height: 1.35,
                    ),
                  ),
                  if (windError != null && weatherOverlayEnabled) ...[
                    const SizedBox(height: 10),
                    Text(
                      windError!,
                      style: const TextStyle(
                        color: Color(0xFF7A4A17),
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (weatherOverlayError != null && weatherOverlayEnabled) ...[
                    const SizedBox(height: 10),
                    Text(
                      weatherOverlayError!,
                      style: const TextStyle(
                        color: Color(0xFF7A4A17),
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if ((windSnapshot != null ||
                          weatherOverlaySnapshot != null) &&
                      weatherOverlayEnabled) ...[
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
                            'Snapshot: ${weatherOverlaySnapshotTimeLabel ?? windSnapshotTimeLabel ?? weatherOverlaySnapshot?.timestampUtc.toIso8601String() ?? windSnapshot?.timestampUtc.toIso8601String() ?? ''}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF112A46),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Animation: $selectedAnimationLabel | Overlay: $selectedOverlayLabel',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF335C67),
                              height: 1.35,
                            ),
                          ),
                          if (weatherOverlaySnapshot != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Color scale: ${weatherOverlaySnapshot!.overlayLabel} (${_weatherUnitLabelForDisplay(weatherOverlaySnapshot!.unitLabel, includeFahrenheitForCelsius: true)}), ${_weatherLevelLabel(weatherOverlaySnapshot!.level)}, every ${weatherOverlaySnapshot!.gridStepDegrees} degrees.',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF335C67),
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Range: ${_weatherValueForDisplay(weatherOverlaySnapshot!.minValue, weatherOverlaySnapshot!.unitLabel, includeFahrenheitForCelsius: true)} to ${_weatherValueForDisplay(weatherOverlaySnapshot!.maxValue, weatherOverlaySnapshot!.unitLabel, includeFahrenheitForCelsius: true)}.',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF335C67),
                                height: 1.35,
                              ),
                            ),
                          ],
                          if (windSnapshot != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              '$selectedAnimationLabel layer: ${_weatherLevelLabel(windSnapshot!.level)} flow, every ${windSnapshot!.gridStepDegrees} degrees.',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF335C67),
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$selectedAnimationLabel speed range: ${windSnapshot!.minSpeedMps.toStringAsFixed(1)} to ${windSnapshot!.maxSpeedMps.toStringAsFixed(1)} m/s.',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF335C67),
                                height: 1.35,
                              ),
                            ),
                            if (overlayMode == _WeatherMode.air ||
                                weatherAnimationMode ==
                                    _WeatherAnimationMode.wind) ...[
                              const SizedBox(height: 6),
                              Text(
                                windAltitudeExplanation,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF335C67),
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                          if (weatherOverlaySnapshot != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Overlay source: ${weatherOverlaySnapshot!.source}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF335C67),
                                height: 1.35,
                              ),
                            ),
                          ],
                          if (windSnapshot != null &&
                              (weatherOverlaySnapshot == null ||
                                  windSnapshot!.source !=
                                      weatherOverlaySnapshot!.source)) ...[
                            const SizedBox(height: 6),
                            Text(
                              '$selectedAnimationLabel source: ${windSnapshot!.source}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF335C67),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _SharedTimePlaybackSection(
                    title: 'Shared Map Time',
                    enabled: weatherOverlayEnabled,
                    astronomyTimeMode: astronomyTimeMode,
                    astronomyDisplayTimeZone: astronomyDisplayTimeZone,
                    astronomyDisplayTimeZoneOptions:
                        astronomyDisplayTimeZoneOptions,
                    astronomyCustomTimeLabel: astronomyCustomTimeLabel,
                    astronomyPlaybackStartLabel: astronomyPlaybackStartLabel,
                    astronomyPlaybackEndLabel: astronomyPlaybackEndLabel,
                    astronomyPlaybackCurrentLabel:
                        astronomyPlaybackCurrentLabel,
                    astronomyPlaybackProgress: astronomyPlaybackProgress,
                    astronomyPlaybackPreset: astronomyPlaybackPreset,
                    astronomyPlaybackSpeed: astronomyPlaybackSpeed,
                    isAstronomyPlaying: isAstronomyPlaying,
                    onAstronomyTimeModeChanged: onAstronomyTimeModeChanged,
                    onAstronomyDisplayTimeZoneChanged:
                        onAstronomyDisplayTimeZoneChanged,
                    onAstronomyDateTimePressed: onAstronomyDateTimePressed,
                    onAstronomyPlaybackPresetChanged:
                        onAstronomyPlaybackPresetChanged,
                    onAstronomyPlaybackSpeedChanged:
                        onAstronomyPlaybackSpeedChanged,
                    onAstronomyPlaybackStartPressed:
                        onAstronomyPlaybackStartPressed,
                    onAstronomyPlaybackEndPressed:
                        onAstronomyPlaybackEndPressed,
                    onAstronomyPlaybackProgressChanged:
                        onAstronomyPlaybackProgressChanged,
                    onAstronomyPlaybackToggle: onAstronomyPlaybackToggle,
                    onAstronomyPlaybackStop: onAstronomyPlaybackStop,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _CollapsiblePanel(
                title: 'Astronomy Overlay',
                subtitle:
                    'Sun, moon, planets, observer, shared time, and events',
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
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: showStars,
                    title: const Text('Stars'),
                    subtitle: const Text(
                      'Bright stars fade through twilight and rotate with sidereal time.',
                    ),
                    onChanged: onShowStarsChanged,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: showConstellations,
                    title: const Text('Constellations'),
                    subtitle: const Text(
                      'Shows the 13 zodiac constellations, including Ophiuchus.',
                    ),
                    onChanged: onShowConstellationsChanged,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: showConstellationsFullSky,
                    title: const Text('Complete constellation guide'),
                    subtitle: const Text(
                      'Keeps the full zodiac outlines visible on the sunlit side too.',
                    ),
                    onChanged: showConstellations
                        ? onShowConstellationsFullSkyChanged
                        : null,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Planets',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF112A46),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: allPlanetsVisible,
                    title: const Text('All planets'),
                    subtitle: const Text(
                      'Toggle Mercury through Neptune together.',
                    ),
                    onChanged: onShowAllPlanetsChanged,
                  ),
                  for (final planetName in _astronomyPlanetNames)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: planetVisibility[planetName] ?? false,
                      title: Text(planetName),
                      onChanged: (value) =>
                          onShowPlanetChanged(planetName, value),
                    ),
                  _SharedTimePlaybackSection(
                    enabled: true,
                    astronomyTimeMode: astronomyTimeMode,
                    astronomyDisplayTimeZone: astronomyDisplayTimeZone,
                    astronomyDisplayTimeZoneOptions:
                        astronomyDisplayTimeZoneOptions,
                    astronomyCustomTimeLabel: astronomyCustomTimeLabel,
                    astronomyPlaybackStartLabel: astronomyPlaybackStartLabel,
                    astronomyPlaybackEndLabel: astronomyPlaybackEndLabel,
                    astronomyPlaybackCurrentLabel:
                        astronomyPlaybackCurrentLabel,
                    astronomyPlaybackProgress: astronomyPlaybackProgress,
                    astronomyPlaybackPreset: astronomyPlaybackPreset,
                    astronomyPlaybackSpeed: astronomyPlaybackSpeed,
                    isAstronomyPlaying: isAstronomyPlaying,
                    onAstronomyTimeModeChanged: onAstronomyTimeModeChanged,
                    onAstronomyDisplayTimeZoneChanged:
                        onAstronomyDisplayTimeZoneChanged,
                    onAstronomyDateTimePressed: onAstronomyDateTimePressed,
                    onAstronomyPlaybackPresetChanged:
                        onAstronomyPlaybackPresetChanged,
                    onAstronomyPlaybackSpeedChanged:
                        onAstronomyPlaybackSpeedChanged,
                    onAstronomyPlaybackStartPressed:
                        onAstronomyPlaybackStartPressed,
                    onAstronomyPlaybackEndPressed:
                        onAstronomyPlaybackEndPressed,
                    onAstronomyPlaybackProgressChanged:
                        onAstronomyPlaybackProgressChanged,
                    onAstronomyPlaybackToggle: onAstronomyPlaybackToggle,
                    onAstronomyPlaybackStop: onAstronomyPlaybackStop,
                    middleChildren: [
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
                    ],
                  ),
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
                          for (final planetName in _astronomyPlanetNames)
                            if (planetVisibility[planetName] ?? false)
                              if (_planetFromSnapshot(
                                astronomySnapshot!,
                                planetName,
                              )
                                  case final planetBody?)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    '$planetName over: ${_formatBodySummary(planetBody.subpoint)}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF335C67),
                                      height: 1.35,
                                    ),
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

  AstronomyBody? _planetFromSnapshot(
    AstronomySnapshot snapshot,
    String planetName,
  ) {
    for (final planet in snapshot.planets) {
      if (planet.name == planetName) {
        return planet;
      }
    }
    return null;
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

class _SharedTimePlaybackSection extends StatelessWidget {
  const _SharedTimePlaybackSection({
    required this.enabled,
    required this.astronomyTimeMode,
    required this.astronomyDisplayTimeZone,
    required this.astronomyDisplayTimeZoneOptions,
    required this.astronomyCustomTimeLabel,
    required this.astronomyPlaybackStartLabel,
    required this.astronomyPlaybackEndLabel,
    required this.astronomyPlaybackCurrentLabel,
    required this.astronomyPlaybackProgress,
    required this.astronomyPlaybackPreset,
    required this.astronomyPlaybackSpeed,
    required this.isAstronomyPlaying,
    required this.onAstronomyTimeModeChanged,
    required this.onAstronomyDisplayTimeZoneChanged,
    required this.onAstronomyDateTimePressed,
    required this.onAstronomyPlaybackPresetChanged,
    required this.onAstronomyPlaybackSpeedChanged,
    required this.onAstronomyPlaybackStartPressed,
    required this.onAstronomyPlaybackEndPressed,
    required this.onAstronomyPlaybackProgressChanged,
    required this.onAstronomyPlaybackToggle,
    required this.onAstronomyPlaybackStop,
    this.title,
    this.middleChildren = const <Widget>[],
  });

  final bool enabled;
  final String? title;
  final List<Widget> middleChildren;
  final _AstronomyTimeMode astronomyTimeMode;
  final String astronomyDisplayTimeZone;
  final List<_ChoiceItem<String>> astronomyDisplayTimeZoneOptions;
  final String astronomyCustomTimeLabel;
  final String astronomyPlaybackStartLabel;
  final String astronomyPlaybackEndLabel;
  final String astronomyPlaybackCurrentLabel;
  final double astronomyPlaybackProgress;
  final _AstronomyPlaybackPreset astronomyPlaybackPreset;
  final _AstronomyPlaybackSpeed astronomyPlaybackSpeed;
  final bool isAstronomyPlaying;
  final ValueChanged<_AstronomyTimeMode?> onAstronomyTimeModeChanged;
  final ValueChanged<String?> onAstronomyDisplayTimeZoneChanged;
  final VoidCallback onAstronomyDateTimePressed;
  final ValueChanged<_AstronomyPlaybackPreset?>
      onAstronomyPlaybackPresetChanged;
  final ValueChanged<_AstronomyPlaybackSpeed?> onAstronomyPlaybackSpeedChanged;
  final VoidCallback onAstronomyPlaybackStartPressed;
  final VoidCallback onAstronomyPlaybackEndPressed;
  final ValueChanged<double> onAstronomyPlaybackProgressChanged;
  final VoidCallback onAstronomyPlaybackToggle;
  final VoidCallback onAstronomyPlaybackStop;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(
            title!,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF112A46),
            ),
          ),
          const SizedBox(height: 10),
        ],
        _SelectionField(
          labelText: 'Map time',
          valueText: astronomyTimeMode == _AstronomyTimeMode.current
              ? 'Current time'
              : 'Custom time',
          currentValue: astronomyTimeMode,
          enabled: enabled,
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
                (option) => option.value == astronomyDisplayTimeZone,
                orElse: () => astronomyDisplayTimeZoneOptions.first,
              )
              .label,
          helperText:
              'Default is local time. Fixed UTC offsets are display-only.',
          currentValue: astronomyDisplayTimeZone,
          enabled: enabled,
          onChanged: onAstronomyDisplayTimeZoneChanged,
          options: astronomyDisplayTimeZoneOptions,
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: enabled && astronomyTimeMode == _AstronomyTimeMode.custom
              ? onAstronomyDateTimePressed
              : null,
          child: Text(
            astronomyTimeMode == _AstronomyTimeMode.current
                ? 'Using current time'
                : astronomyCustomTimeLabel,
          ),
        ),
        if (middleChildren.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...middleChildren,
        ],
        const SizedBox(height: 14),
        const Text(
          'Time playback',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Color(0xFF112A46),
          ),
        ),
        const SizedBox(height: 10),
        _SelectionField(
          labelText: 'Range',
          valueText: _playbackPresetLabel(astronomyPlaybackPreset),
          currentValue: astronomyPlaybackPreset,
          enabled: enabled,
          onChanged: onAstronomyPlaybackPresetChanged,
          options: [
            for (final preset in _AstronomyPlaybackPreset.values)
              _ChoiceItem(
                value: preset,
                label: _playbackPresetLabel(preset),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _SelectionField(
          labelText: 'Playback speed',
          valueText: _playbackSpeedLabel(astronomyPlaybackSpeed),
          currentValue: astronomyPlaybackSpeed,
          enabled: enabled,
          onChanged: onAstronomyPlaybackSpeedChanged,
          options: [
            for (final speed in _AstronomyPlaybackSpeed.values)
              _ChoiceItem(
                value: speed,
                label: _playbackSpeedLabel(speed),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: enabled ? onAstronomyPlaybackStartPressed : null,
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
                onPressed: enabled ? onAstronomyPlaybackEndPressed : null,
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
              onChanged: enabled ? onAstronomyPlaybackProgressChanged : null,
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
                onPressed: enabled ? onAstronomyPlaybackToggle : null,
                child: Text(isAstronomyPlaying ? 'Pause' : 'Play'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: enabled &&
                        astronomyTimeMode == _AstronomyTimeMode.custom &&
                        (isAstronomyPlaying || astronomyPlaybackProgress > 0)
                    ? onAstronomyPlaybackStop
                    : null,
                child: const Text('Restart'),
              ),
            ),
          ],
        ),
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
