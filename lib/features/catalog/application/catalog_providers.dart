import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/di/core_providers.dart';
import '../data/catalog_repository.dart';
import '../data/radio_browser_api.dart';
import '../data/youtube_api.dart';
import '../domain/track.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return CatalogRepository(YouTubeApi(client), RadioBrowserApi(client), ref.watch(localStoreProvider));
});

/// Device region → regional charts and "radio near you". Falls back to India.
final regionCodeProvider = Provider<String>((ref) {
  final code = PlatformDispatcher.instance.locale.countryCode;
  return (code == null || code.isEmpty) ? 'IN' : code.toUpperCase();
});

/// False when the build has no YOUTUBE_API_KEY (the app then runs radio-only).
final youtubeEnabledProvider = Provider<bool>((ref) => AppConfig.youtubeEnabled);

final trendingVideosProvider = FutureProvider.autoDispose<List<Track>>(
  (ref) => ref.watch(catalogRepositoryProvider).trendingVideos(regionCode: ref.watch(regionCodeProvider)),
);

/// YouTube search — only ever triggered by an explicit submit (100 quota units).
final videoSearchProvider = FutureProvider.autoDispose.family<List<Track>, String>(
  (ref, query) => ref.watch(catalogRepositoryProvider).searchVideos(query, regionCode: ref.watch(regionCodeProvider)),
);

final nearbyStationsProvider = FutureProvider.autoDispose<List<Track>>(
  (ref) => ref.watch(catalogRepositoryProvider).topStations(countryCode: ref.watch(regionCodeProvider)),
);

final stationsByTagProvider = FutureProvider.autoDispose.family<List<Track>, String>(
  (ref, tag) => ref.watch(catalogRepositoryProvider).stationsByTag(tag),
);

final stationSearchProvider = FutureProvider.autoDispose.family<List<Track>, String>(
  (ref, query) => ref.watch(catalogRepositoryProvider).searchStations(query),
);
