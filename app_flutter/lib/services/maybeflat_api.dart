import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/astronomy_event.dart';
import '../models/astronomy_snapshot.dart';
import '../models/city_search_result.dart';
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
  }) : baseUrl = _normalizeBaseUrl(baseUrl ?? _defaultBaseUrl()),
       _client = client ?? http.Client();

  final String baseUrl;
  final Duration healthTimeout;
  final Duration sceneTimeout;
  final Duration actionTimeout;
  final http.Client _client;

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

  Future<bool> checkHealth() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(healthTimeout);
      if (response.statusCode != 200) {
        return false;
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return payload['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<MapScene> loadScene({
    String detail = 'desktop',
    bool includeStateBoundaries = false,
  }) async {
    final response = await _client
        .get(
          Uri.parse(
            '$baseUrl/map/scene?detail=$detail&include_state_boundaries=$includeStateBoundaries',
          ),
        )
        .timeout(sceneTimeout);
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
    final response = await _client
        .post(
          Uri.parse('$baseUrl/map/transform'),
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
    final response = await _client
        .post(
          Uri.parse('$baseUrl/map/measure'),
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

    final uri = Uri.parse('$baseUrl/map/astronomy').replace(
      queryParameters: queryParameters,
    );
    final response = await _client.get(uri).timeout(sceneTimeout);
    if (response.statusCode != 200) {
      throw Exception('Failed to load astronomy snapshot: ${response.statusCode}');
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

    final uri = Uri.parse('$baseUrl/map/events').replace(
      queryParameters: queryParameters,
    );
    final response = await _client.get(uri).timeout(sceneTimeout);
    if (response.statusCode != 200) {
      throw Exception('Failed to load astronomy events: ${response.statusCode}');
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
    final uri = Uri.parse('$baseUrl/map/cities/search').replace(
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
}
