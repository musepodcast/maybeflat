import 'dart:math';

import 'browser_storage.dart';

class ClientIdentity {
  ClientIdentity._();

  static final ClientIdentity instance = ClientIdentity._();

  static const String _visitorIdKey = 'maybeflat_visitor_id';
  static const String _sessionIdKey = 'maybeflat_session_id';
  static const String _sessionTouchedAtKey = 'maybeflat_session_touched_at';
  static const String _adminTokenKey = 'maybeflat_admin_token';
  static const Duration _sessionTimeout = Duration(minutes: 30);

  final BrowserStorage _storage = createBrowserStorage();
  final Random _random = Random();

  bool _initialized = false;
  String? _visitorId;
  String? _sessionId;

  Future<void> initialize() async {
    if (_initialized) {
      _touchSession();
      return;
    }

    _visitorId = _storage.getPersistent(_visitorIdKey);
    if (_visitorId == null || _visitorId!.isEmpty) {
      _visitorId = _generateId('visitor');
      _storage.setPersistent(_visitorIdKey, _visitorId!);
    }

    _sessionId = _storage.getSession(_sessionIdKey);
    final lastTouchedRaw = _storage.getSession(_sessionTouchedAtKey);
    final lastTouched = DateTime.tryParse(lastTouchedRaw ?? '');
    final isExpired = lastTouched == null ||
        DateTime.now().difference(lastTouched) > _sessionTimeout;
    if (_sessionId == null || _sessionId!.isEmpty || isExpired) {
      _sessionId = _generateId('session');
      _storage.setSession(_sessionIdKey, _sessionId!);
    }

    _touchSession();
    _initialized = true;
  }

  String get visitorId {
    if (_visitorId == null || _visitorId!.isEmpty) {
      throw StateError('ClientIdentity.initialize must run before access.');
    }
    return _visitorId!;
  }

  String get sessionId {
    if (_sessionId == null || _sessionId!.isEmpty) {
      throw StateError('ClientIdentity.initialize must run before access.');
    }
    return _sessionId!;
  }

  Map<String, String> trackingHeaders() {
    _touchSession();
    return <String, String>{
      'X-Maybeflat-Visitor-ID': visitorId,
      'X-Maybeflat-Session-ID': sessionId,
    };
  }

  String currentPath() {
    final path = Uri.base.path.trim();
    return path.isEmpty ? '/' : path;
  }

  String? get adminToken {
    final token = _storage.getSession(_adminTokenKey)?.trim();
    if (token == null || token.isEmpty) {
      return null;
    }
    return token;
  }

  void saveAdminToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      clearAdminToken();
      return;
    }
    _storage.setSession(_adminTokenKey, trimmed);
  }

  void clearAdminToken() {
    _storage.removeSession(_adminTokenKey);
  }

  void _touchSession() {
    _storage.setSession(
      _sessionTouchedAtKey,
      DateTime.now().toIso8601String(),
    );
  }

  String _generateId(String prefix) {
    final buffer = StringBuffer(prefix)..write('_');
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    buffer.write(timestamp);
    for (var index = 0; index < 4; index += 1) {
      buffer.write(_random.nextInt(1 << 16).toRadixString(16).padLeft(4, '0'));
    }
    return buffer.toString();
  }
}
