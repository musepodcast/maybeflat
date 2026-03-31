import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/astronomy_event.dart';
import '../models/astronomy_snapshot.dart';
import '../models/measure_result.dart';
import '../models/map_scene.dart';
import '../models/place_marker.dart';

class MaybeflatApi {
  MaybeflatApi({
    this.baseUrl = 'http://127.0.0.1:8002',
    this.healthTimeout = const Duration(seconds: 6),
    this.sceneTimeout = const Duration(seconds: 20),
    this.actionTimeout = const Duration(seconds: 10),
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final Duration healthTimeout;
  final Duration sceneTimeout;
  final Duration actionTimeout;
  final http.Client _client;

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
}
