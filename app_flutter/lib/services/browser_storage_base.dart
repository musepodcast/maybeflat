abstract class BrowserStorage {
  String? getPersistent(String key);

  void setPersistent(String key, String value);

  void removePersistent(String key);

  String? getSession(String key);

  void setSession(String key, String value);

  void removeSession(String key);
}
