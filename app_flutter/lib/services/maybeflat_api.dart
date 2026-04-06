import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/astronomy_event.dart';
import '../models/astronomy_snapshot.dart';
import '../models/city_search_result.dart';
import '../models/map_label.dart';
import '../models/measure_result.dart';
import '../models/map_scene.dart';
import '../models/place_marker.dart';

class MaybeflatApi {
  MaybeflatApi({
    String? baseUrl,
    this.healthTimeout = const Duration(seconds: 6),
    this.sceneTimeout = const Duration(seconds: 20),
    this.actionTimeout = const Duration(seconds: 10),
    http.Client? client,
  })  : _baseUrlIsExplicit = (baseUrl != null && baseUrl.trim().isNotEmpty) ||
            const String.fromEnvironment(
              'MAYBEFLAT_API_BASE_URL',
              defaultValue: '',
            ).isNotEmpty,
        baseUrl = _normalizeBaseUrl(baseUrl ?? _defaultBaseUrl()),
        _client = client ?? http.Client();

  final String baseUrl;
  final Duration healthTimeout;
  final Duration sceneTimeout;
  final Duration actionTimeout;
  final http.Client _client;
  final bool _baseUrlIsExplicit;
  String? _resolvedBaseUrl;
  Future<String>? _baseUrlResolution;

  static String _defaultBaseUrl() {
    const configuredBaseUrl = String.fromEnvironment(
      'MAYBEFLAT_API_BASE_URL',
      defaultValue: '',
    );
    if (configuredBaseUrl.isNotEmpty) {
      return configuredBaseUrl;
    }

    if (!kIsWeb) {
      return 'http://127.0.0.1:8002';
    }

    final host = Uri.base.host.toLowerCase();
    if (host == 'localhost' || host == '127.0.0.1') {
      return 'http://127.0.0.1:8002';
    }

    return '/api';
  }

  static String _normalizeBaseUrl(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) {
      return 'http://127.0.0.1:8002';
    }

    final parsed = Uri.parse(trimmed);
    final resolved = parsed.hasScheme || parsed.hasAuthority
        ? parsed
        : Uri.base.resolveUri(parsed);
    final normalizedPath = resolved.path.endsWith('/')
        ? resolved.path.substring(0, resolved.path.length - 1)
        : resolved.path;
    return resolved.replace(path: normalizedPath).toString();
  }

  static List<String> _defaultCandidateBaseUrls() {
    return const [
      'http://127.0.0.1:8002',
      'http://10.0.2.2:8002',
      'http://10.0.3.2:8002',
    ];
  }

  Future<bool> _checkHealthAt(
    String candidateBaseUrl, {
    Duration? timeout,
  }) async {
    try {
      final response = await _client
          .get(Uri.parse('$candidateBaseUrl/health'))
          .timeout(timeout ?? healthTimeout);
      if (response.statusCode != 200) {
        return false;
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return payload['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<String> _resolveDefaultBaseUrl() async {
    const probeTimeout = Duration(seconds: 2);
    for (final candidateBaseUrl in _defaultCandidateBaseUrls()) {
      final isHealthy = await _checkHealthAt(
        candidateBaseUrl,
        timeout: probeTimeout,
      );
      if (isHealthy) {
        _resolvedBaseUrl = candidateBaseUrl;
        return candidateBaseUrl;
      }
    }

    _resolvedBaseUrl = baseUrl;
    return baseUrl;
  }

  Future<String> _effectiveBaseUrl() async {
    if (_baseUrlIsExplicit || kIsWeb) {
      return baseUrl;
    }

    if (_resolvedBaseUrl != null) {
      return _resolvedBaseUrl!;
    }

    final pendingResolution = _baseUrlResolution;
    if (pendingResolution != null) {
      return pendingResolution;
    }

    final nextResolution = _resolveDefaultBaseUrl();
    _baseUrlResolution = nextResolution;
    try {
      return await nextResolution;
    } finally {
      if (identical(_baseUrlResolution, nextResolution)) {
        _baseUrlResolution = null;
      }
    }
  }

  Future<Uri> _buildUri(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final activeBaseUrl = await _effectiveBaseUrl();
    return Uri.parse('$activeBaseUrl$path').replace(
      queryParameters: queryParameters,
    );
  }

  Future<bool> checkHealth() async {
    if (_baseUrlIsExplicit || kIsWeb) {
      return _checkHealthAt(baseUrl);
    }

    for (final candidateBaseUrl in _defaultCandidateBaseUrls()) {
      final isHealthy = await _checkHealthAt(candidateBaseUrl);
      if (isHealthy) {
        _resolvedBaseUrl = candidateBaseUrl;
        return true;
      }
    }

    _resolvedBaseUrl = baseUrl;
    return false;
  }

  Future<MapScene> loadScene({
    String detail = 'desktop',
    bool includeStateBoundaries = false,
  }) async {
    final uri = await _buildUri(
      '/map/scene',
      queryParameters: {
        'detail': detail,
        'include_state_boundaries': '$includeStateBoundaries',
      },
    );
    final response = await _client.get(uri).timeout(sceneTimeout);
    if (response.statusCode != 200) {
      throw Exception('Failed to load scene: ${response.statusCode}');
    }

    return MapScene.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<PlaceMarker> transformPoint({
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    final uri = await _buildUri('/map/transform');
    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'latitude': latitude,
            'longitude': longitude,
          }),
        )
        .timeout(actionTimeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to transform point: ${response.statusCode}');
    }

    return PlaceMarker.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<MeasureResult> measurePoints({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) async {
    final uri = await _buildUri('/map/measure');
    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'start_latitude': startLatitude,
            'start_longitude': startLongitude,
            'end_latitude': endLatitude,
            'end_longitude': endLongitude,
          }),
        )
        .timeout(actionTimeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to measure points: ${response.statusCode}');
    }

    return MeasureResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AstronomySnapshot> loadAstronomySnapshot({
    DateTime? timestampUtc,
    String? observerName,
    double? observerLatitude,
    double? observerLongitude,
    int pathHours = 24,
    int pathStepMinutes = 30,
  }) async {
    final queryParameters = <String, String>{
      'path_hours': '$pathHours',
      'path_step_minutes': '$pathStepMinutes',
    };
    if (timestampUtc != null) {
      queryParameters['timestamp_utc'] = timestampUtc.toUtc().toIso8601String();
    }
    if (observerLatitude != null && observerLongitude != null) {
      queryParameters['observer_latitude'] = '$observerLatitude';
      queryParameters['observer_longitude'] = '$observerLongitude';
      if (observerName != null && observerName.trim().isNotEmpty) {
        queryParameters['observer_name'] = observerName.trim();
      }
    }

    final uri = await _buildUri(
      '/map/astronomy',
      queryParameters: queryParameters,
    );
    final response = await _client.get(uri).timeout(sceneTimeout);
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to load astronomy snapshot: ${response.statusCode}');
    }

    return AstronomySnapshot.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<AstronomyEvent>> loadAstronomyEvents({
    String eventType = 'eclipse',
    String? subgroup,
    DateTime? fromTimestampUtc,
    int limit = 24,
  }) async {
    final queryParameters = <String, String>{
      'event_type': eventType,
      'limit': '$limit',
    };
    if (subgroup != null && subgroup.isNotEmpty) {
      queryParameters['subgroup'] = subgroup;
    }
    if (fromTimestampUtc != null) {
      queryParameters['from_timestamp_utc'] =
          fromTimestampUtc.toUtc().toIso8601String();
    }

    final uri = await _buildUri(
      '/map/events',
      queryParameters: queryParameters,
    );
    final response = await _client.get(uri).timeout(sceneTimeout);
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to load astronomy events: ${response.statusCode}');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return (payload['events'] as List<dynamic>? ?? const [])
        .map((event) => AstronomyEvent.fromJson(event as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<CitySearchResult>> searchCities({
    required String query,
    int limit = 12,
  }) async {
    final uri = await _buildUri(
      '/map/cities/search',
      queryParameters: {
        'q': query,
        'limit': '$limit',
      },
    );
    final response = await _client.get(uri).timeout(actionTimeout);
    if (response.statusCode != 200) {
      throw Exception('Failed to search cities: ${response.statusCode}');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return (payload['results'] as List<dynamic>? ?? const [])
        .map(
          (result) => CitySearchResult.fromJson(result as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<List<MapLabel>> loadCityLabels({
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
    int limit = 400,
  }) async {
    final uri = await _buildUri(
      '/map/labels/cities',
      queryParameters: {
        'min_x': '$minX',
        'max_x': '$maxX',
        'min_y': '$minY',
        'max_y': '$maxY',
        'limit': '$limit',
      },
    );
    final response = await _client.get(uri).timeout(sceneTimeout);
    if (response.statusCode != 200) {
      throw Exception('Failed to load city labels: ${response.statusCode}');
    }

    final payload = jsonDecode(response.body) as List<dynamic>;
    return payload
        .map((label) => MapLabel.fromJson(label as Map<String, dynamic>))
        .toList(growable: false);
  }
}
