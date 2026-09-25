import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local preferences. Anything here is cheap, private to the device and
/// deliberately kept OUT of Firestore to save reads/writes (e.g. history).
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferencesWithCache _prefs;

  static const _kThemeMode = 'theme_mode';
  static const _kRecentSearches = 'recent_searches';
  static const _kRecentTracks = 'recent_tracks';
  static const _kVideoSearchCache = 'video_search_cache';
  static const _kRooms = 'rooms';

  static Future<LocalStore> create() async {
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: {_kThemeMode, _kRecentSearches, _kRecentTracks, _kVideoSearchCache, _kRooms},
      ),
    );
    return LocalStore(prefs);
  }

  ThemeMode get themeMode =>
      ThemeMode.values.firstWhere((m) => m.name == _prefs.getString(_kThemeMode), orElse: () => ThemeMode.dark);

  Future<void> setThemeMode(ThemeMode mode) => _prefs.setString(_kThemeMode, mode.name);

  List<String> get recentSearches => _prefs.getStringList(_kRecentSearches) ?? const [];

  Future<void> addRecentSearch(String query) {
    final q = query.trim();
    if (q.isEmpty) return Future.value();
    final next = [q, ...recentSearches.where((s) => s.toLowerCase() != q.toLowerCase())].take(8).toList();
    return _prefs.setStringList(_kRecentSearches, next);
  }

  Future<void> clearRecentSearches() => _prefs.remove(_kRecentSearches);

  /// Recently played tracks, stored as compact JSON maps (max 30).
  List<Map<String, Object?>> get recentTracks {
    final raw = _prefs.getStringList(_kRecentTracks) ?? const [];
    return [
      for (final s in raw)
        if (jsonDecode(s) case final Map<String, Object?> m) m,
    ];
  }

  Future<void> pushRecentTrack(String id, Map<String, Object?> json) {
    final next = [json, ...recentTracks.where((m) => m['id'] != id)].take(30).map(jsonEncode).toList();
    return _prefs.setStringList(_kRecentTracks, next);
  }

  /// Rooms joined on this device (see `RememberedRooms`), as JSON.
  Map<String, Object?>? get rooms {
    final raw = _prefs.getString(_kRooms);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> setRooms(Map<String, Object?> json) => _prefs.setString(_kRooms, jsonEncode(json));

  /// Persisted YouTube search results: a search costs 100 of the API's 10,000
  /// daily units, so the same query is never paid for twice within [ttl],
  /// even across app restarts. Bounded to [_maxCachedQueries] entries.
  static const _maxCachedQueries = 40;

  List<Map<String, Object?>>? cachedVideoSearch(String query, {required Duration ttl}) {
    final entry = _videoCache()[query];
    if (entry is! Map<String, Object?>) return null;
    final at = entry['at'];
    if (at is! int || DateTime.now().millisecondsSinceEpoch - at > ttl.inMilliseconds) return null;
    return [
      for (final item in (entry['items'] as List<Object?>? ?? const []))
        if (item is Map<String, Object?>) item,
    ];
  }

  Future<void> putVideoSearch(String query, List<Map<String, Object?>> items) {
    final cache = _videoCache()
      ..remove(query)
      ..[query] = {'at': DateTime.now().millisecondsSinceEpoch, 'items': items};
    while (cache.length > _maxCachedQueries) {
      cache.remove(cache.keys.first); // oldest first (insertion order)
    }
    return _prefs.setString(_kVideoSearchCache, jsonEncode(cache));
  }

  Map<String, Object?> _videoCache() {
    final raw = _prefs.getString(_kVideoSearchCache);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : {};
    } on FormatException {
      return {};
    }
  }
}
