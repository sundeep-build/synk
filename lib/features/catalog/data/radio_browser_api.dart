import '../../../core/config/app_config.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import '../domain/track.dart';

/// Radio Browser — free, community-run directory of 50k+ stations.
/// Docs: https://api.radio-browser.info
class RadioBrowserApi {
  RadioBrowserApi(this._client);

  final ApiClient _client;
  int _hostIndex = 0;

  Future<List<Track>> search({String? name, String? tag, String? countryCode, int limit = 30}) async {
    final query = {
      'order': 'clickcount',
      'reverse': 'true',
      'hidebroken': 'true',
      // HTTPS only: cleartext streams are blocked by Android/iOS by default.
      'is_https': 'true',
      'limit': '$limit',
      'name': ?name,
      'tag': ?tag,
      'countrycode': ?countryCode,
    };

    AppException? lastError;
    // Rotate through mirrors; stick with whichever one answered last.
    for (var attempt = 0; attempt < AppConfig.radioBrowserHosts.length; attempt++) {
      final host = AppConfig.radioBrowserHosts[_hostIndex];
      try {
        final body = await _client.getJson(
          Uri.parse('$host/json/stations/search').replace(queryParameters: query),
          retries: 0,
        );
        return _parseList(body);
      } on AppException catch (e) {
        lastError = e;
        _hostIndex = (_hostIndex + 1) % AppConfig.radioBrowserHosts.length;
      }
    }
    throw lastError ?? const NetworkException();
  }

  List<Track> _parseList(Object? body) {
    if (body is! List<Object?>) return const [];
    final seen = <String>{};
    return [
      for (final raw in body)
        if (raw is Map<Object?, Object?>)
          if (mapStation(raw) case final Track t)
            // Directories often list the same stream several times.
            if (seen.add(t.streamUrl)) t,
    ];
  }

  static Track? mapStation(Json json) {
    final uuid = json.str('stationuuid');
    final url = json.str('url_resolved', json.str('url'));
    if (uuid.isEmpty || !url.startsWith('https://')) return null;
    final favicon = json.str('favicon');
    final tags = json.str('tags').split(',').map((t) => t.trim()).where((t) => t.isNotEmpty);
    final country = json.str('country');
    return Track(
      id: 'radio:$uuid',
      source: TrackSource.radio,
      title: json.str('name', 'Radio').trim(),
      artist: country.isNotEmpty ? 'Live · $country' : 'Live radio',
      streamUrl: url,
      artworkUrl: favicon.startsWith('https://') ? favicon : null,
      genre: tags.isEmpty ? null : tags.first,
    );
  }
}
