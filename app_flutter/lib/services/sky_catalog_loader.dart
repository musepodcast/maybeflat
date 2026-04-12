import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/sky_catalog.dart';

class SkyCatalogLoader {
  SkyCatalogLoader._();

  static final SkyCatalogLoader instance = SkyCatalogLoader._();
  static const String _assetPath = 'assets/astronomy/sky_catalog.json';

  SkyCatalog? _catalog;
  Future<SkyCatalog>? _pendingLoad;

  Future<SkyCatalog> load() {
    final cachedCatalog = _catalog;
    if (cachedCatalog != null) {
      return Future<SkyCatalog>.value(cachedCatalog);
    }

    final pendingLoad = _pendingLoad;
    if (pendingLoad != null) {
      return pendingLoad;
    }

    final nextLoad = _loadFromBundle();
    _pendingLoad = nextLoad;
    return nextLoad;
  }

  Future<SkyCatalog> _loadFromBundle() async {
    try {
      final rawJson = await rootBundle.loadString(_assetPath);
      final payload = jsonDecode(rawJson) as Map<String, dynamic>;
      final loadedCatalog = SkyCatalog.fromJson(payload);
      _catalog = loadedCatalog;
      return loadedCatalog;
    } finally {
      _pendingLoad = null;
    }
  }
}
