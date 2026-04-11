import 'dart:html' as html;

import 'browser_storage_base.dart';

class _WebBrowserStorage implements BrowserStorage {
  @override
  String? getPersistent(String key) => html.window.localStorage[key];

  @override
  String? getSession(String key) => html.window.sessionStorage[key];

  @override
  void removePersistent(String key) {
    html.window.localStorage.remove(key);
  }

  @override
  void removeSession(String key) {
    html.window.sessionStorage.remove(key);
  }

  @override
  void setPersistent(String key, String value) {
    html.window.localStorage[key] = value;
  }

  @override
  void setSession(String key, String value) {
    html.window.sessionStorage[key] = value;
  }
}

BrowserStorage createPlatformBrowserStorage() => _WebBrowserStorage();
