import 'browser_storage_base.dart';

class _InMemoryBrowserStorage implements BrowserStorage {
  final Map<String, String> _persistent = <String, String>{};
  final Map<String, String> _session = <String, String>{};

  @override
  String? getPersistent(String key) => _persistent[key];

  @override
  String? getSession(String key) => _session[key];

  @override
  void removePersistent(String key) {
    _persistent.remove(key);
  }

  @override
  void removeSession(String key) {
    _session.remove(key);
  }

  @override
  void setPersistent(String key, String value) {
    _persistent[key] = value;
  }

  @override
  void setSession(String key, String value) {
    _session[key] = value;
  }
}

BrowserStorage createPlatformBrowserStorage() => _InMemoryBrowserStorage();
