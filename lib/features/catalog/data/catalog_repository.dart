import 'dart:math';

import '../../../core/network/ttl_cache.dart';
import '../../../core/storage/local_store.dart';
import '../domain/track.dart';
import 'radio_browser_api.dart';
import 'youtube_api.dart';

/// Single entry point for "things you can play": YouTube (songs & videos, on
/// screen) and live radio (background). UI and rooms never talk to a provider
/// directly, so adding a licensed catalog later is a local change.
class CatalogRepository {
  CatalogRepository(this._youtube, this._radio, this._store);

  final YouTubeApi _youtube;
  final RadioBrowserApi _radio;
  final LocalStore _store;
  final TtlCache<String, List<Track>> _cache = TtlCache(maxEntries: 48, ttl: const Duration(minutes: 30));
  final Random _random = Random();

  static const _searchTtl = Duration(hours: 12);

  // ── YouTube ──────────────────────────────────────────────────────────────
  /// Trending music videos for the region (1 quota unit, cached 30 min).
  Future<List<Track>> trendingVideos({required String regionCode}) =>
      _cache.getOrLoad('yt:trending:$regionCode', () => _youtube.trendingMusic(regionCode: regionCode));

  /// YouTube search (100 quota units). Cached in memory and on disk for 12h so
  /// a query is paid for at most twice a day per device.
  Future<List<Track>> searchVideos(String query, {String? regionCode}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return Future.value(const []);
    final key = 'yt:search:$regionCode:$q';
    return _cache.getOrLoad(key, () async {
      final persisted = _store.cachedVideoSearch(key, ttl: _searchTtl);
      if (persisted != null) {
        return [
          for (final json in persisted)
            if (Track.tryParse(json) case final Track t) t,
        ];
      }
      final fresh = await _youtube.search(q, regionCode: regionCode);
      await _store.putVideoSearch(key, [for (final t in fresh) t.toJson()]);
      return fresh;
    });
  }

  // ── Radio ────────────────────────────────────────────────────────────────
  Future<List<Track>> topStations({String? countryCode}) =>
      _cache.getOrLoad('stations:country:$countryCode', () => _radio.search(countryCode: countryCode));

  Future<List<Track>> stationsByTag(String tag) => _cache.getOrLoad('stations:tag:$tag', () => _radio.search(tag: tag));

  Future<List<Track>> searchStations(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return Future.value(const []);
    return _cache.getOrLoad('stations:name:$q', () => _radio.search(name: q));
  }

  // ── Autoplay ─────────────────────────────────────────────────────────────
  /// Next video when a room's queue runs dry: a random pick from the top of the
  /// regional music chart, skipping what the room played recently. Uses the
  /// cached chart, so autoplay costs no extra quota.
  Future<Track?> nextSimilar(Track? current, {required String regionCode, Set<String> exclude = const {}}) async {
    final pool = await trendingVideos(regionCode: regionCode);
    final candidates = pool.where((t) => !exclude.contains(t.id) && t.id != current?.id).toList();
    if (candidates.isEmpty) return null;
    return candidates[_random.nextInt(min(12, candidates.length))];
  }
}
