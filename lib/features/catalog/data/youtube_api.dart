import '../../../core/config/app_config.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import '../domain/track.dart';

/// YouTube Data API v3 — discovery only (search, charts, metadata).
/// Playback always goes through the official IFrame player (see YouTubeEngine).
///
/// Quota (default 10,000 units/day per project):
/// * `videos.list`  = 1 unit   → charts and durations
/// * `search.list`  = 100 units → user search (cached by CatalogRepository)
class YouTubeApi {
  YouTubeApi(this._client);

  final ApiClient _client;

  static const _base = 'https://www.googleapis.com/youtube/v3';
  static const _musicCategory = '10';

  Map<String, String> get _headers => const {
    'X-Android-Package': AppConfig.androidPackage,
    'X-Android-Cert': AppConfig.androidCertSha1,
  };

  Uri _uri(String path, Map<String, String> query) =>
      Uri.parse('$_base$path').replace(queryParameters: {...query, 'key': AppConfig.youtubeApiKey});

  /// Most popular music videos in [regionCode] (1 unit).
  Future<List<Track>> trendingMusic({required String regionCode, int maxResults = 50}) async {
    final body = await _get('/videos', {
      'part': 'snippet,contentDetails,status',
      'chart': 'mostPopular',
      'videoCategoryId': _musicCategory,
      'regionCode': regionCode,
      'maxResults': '$maxResults',
    });
    return _mapVideos(body);
  }

  /// Embeddable, non-live videos matching [query] (100 + 1 units).
  Future<List<Track>> search(String query, {String? regionCode, int maxResults = 25}) async {
    final body = await _get('/search', {
      'part': 'snippet',
      'type': 'video',
      'q': query,
      'maxResults': '$maxResults',
      'videoEmbeddable': 'true',
      'videoSyndicated': 'true',
      'safeSearch': 'moderate',
      'regionCode': ?regionCode,
    });
    final ids = [
      if (body is Map<Object?, Object?>)
        for (final item in body.list('items'))
          if (item is Map<Object?, Object?>)
            if (item.json('id')?.strOrNull('videoId') case final String id) id,
    ];
    if (ids.isEmpty) return const [];
    // search.list has no durations; one videos.list call fetches them for all.
    final details = await _get('/videos', {'part': 'snippet,contentDetails,status', 'id': ids.join(',')});
    final byId = {for (final t in _mapVideos(details)) t.youtubeId: t};
    return [for (final id in ids) ?byId[id]]; // keep search ranking order
  }

  Future<Object?> _get(String path, Map<String, String> query) async {
    if (!AppConfig.youtubeEnabled) throw const YouTubeNotConfiguredException();
    try {
      return await _client.getJson(_uri(path, query), headers: _headers, retries: 1);
    } on HttpStatusException catch (e) {
      final reason = '${e.cause}';
      if (e.statusCode == 403 && (reason.contains('quotaExceeded') || reason.contains('rateLimitExceeded'))) {
        throw ServiceUnavailableException("YouTube's daily limit is reached. Radio still works — try videos later.", e);
      }
      if (e.statusCode == 400 || e.statusCode == 403) {
        throw ServiceUnavailableException('YouTube is not set up correctly for this app build.', e);
      }
      rethrow;
    }
  }

  static List<Track> _mapVideos(Object? body) {
    if (body is! Map<Object?, Object?>) return const [];
    return [
      for (final raw in body.list('items'))
        if (raw is Map<Object?, Object?>)
          if (mapVideo(raw) case final Track t) t,
    ];
  }

  /// Maps a `videos.list` item; drops live streams, premieres and videos that
  /// can't be embedded (these are what show "Video unavailable" in other apps).
  static Track? mapVideo(Json item) {
    final id = item.str('id');
    final snippet = item.json('snippet');
    final status = item.json('status');
    if (id.length != 11 || snippet == null) return null;
    if (status != null && !status.boolean('embeddable', true)) return null;
    if (snippet.str('liveBroadcastContent', 'none') != 'none') return null;
    final durationMs = parseIsoDuration(item.json('contentDetails')?.str('duration') ?? '') * 1000;
    if (durationMs <= 0) return null;
    final thumbs = snippet.json('thumbnails');
    String? thumb(String size) => thumbs?.json(size)?.strOrNull('url');
    return Track(
      id: 'yt:$id',
      source: TrackSource.youtube,
      title: decodeEntities(snippet.str('title', 'Untitled')),
      artist: decodeEntities(snippet.str('channelTitle', 'YouTube')).replaceAll(RegExp(r' - Topic$'), ''),
      streamUrl: 'https://www.youtube.com/watch?v=$id',
      artworkUrl: thumb('high') ?? thumb('medium') ?? thumb('default'),
      durationMs: durationMs,
    );
  }

  /// ISO-8601 duration (`PT1H2M3S`, `P1DT2S`) → seconds. Invalid → 0.
  static int parseIsoDuration(String iso) {
    final m = RegExp(r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$').firstMatch(iso);
    if (m == null) return 0;
    int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
    return g(1) * 86400 + g(2) * 3600 + g(3) * 60 + g(4);
  }

  /// The API returns HTML-escaped titles ("Rock &amp; Roll", "Don&#39;t").
  /// `&amp;` is decoded last so "&amp;#39;" stays a literal "&#39;".
  static String decodeEntities(String s) => s
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}
