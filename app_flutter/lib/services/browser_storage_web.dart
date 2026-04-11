import 'package:web/web.dart' as web;

import 'browser_storage_base.dart';

class _WebBrowserStorage implements BrowserStorage {
  @override
  String? getPersistent(String key) => web.window.localStorage.getItem(key);

  @override
  String? getSession(String key) => web.window.sessionStorage.getItem(key);

  @override
  void removePersistent(String key) {
    web.window.localStorage.removeItem(key);
  }

  @override
  void removeSession(String key) {
    web.window.sessionStorage.removeItem(key);
  }

  @override
  void setPersistent(String key, String value) {
    web.window.localStorage.setItem(key, value);
  }

  @override
  void setSession(String key, String value) {
    web.window.sessionStorage.setItem(key, value);
  }
}

BrowserStorage createPlatformBrowserStorage() => _WebBrowserStorage();
