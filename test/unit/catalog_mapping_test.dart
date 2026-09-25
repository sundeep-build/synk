import 'package:flutter_test/flutter_test.dart';
import 'package:synk/features/catalog/data/radio_browser_api.dart';
import 'package:synk/features/catalog/data/youtube_api.dart';
import 'package:synk/features/catalog/domain/track.dart';

void main() {
  group('YouTubeApi.mapVideo', () {
    Map<Object?, Object?> video({
      String id = 'dQw4w9WgXcQ',
      bool embeddable = true,
      String live = 'none',
      String duration = 'PT3M33S',
    }) => {
      'id': id,
      'snippet': {
        'title': 'Rock &amp; Roll &#39;Anthem&#39;',
        'channelTitle': 'Artist - Topic',
        'liveBroadcastContent': live,
        'thumbnails': {
          'high': {'url': 'https://i.ytimg.com/vi/$id/hqdefault.jpg'},
        },
      },
      'contentDetails': {'duration': duration},
      'status': {'embeddable': embeddable},
    };

    test('maps an embeddable video', () {
      final t = YouTubeApi.mapVideo(video())!;
      expect(t.id, 'yt:dQw4w9WgXcQ');
      expect(t.youtubeId, 'dQw4w9WgXcQ');
      expect(t.isYouTube, isTrue);
      expect(t.canPlayInBackground, isFalse, reason: 'YouTube policy: no background play');
      expect(t.title, "Rock & Roll 'Anthem'");
      expect(t.artist, 'Artist', reason: 'auto-generated " - Topic" channels are cleaned up');
      expect(t.durationMs, 213000);
      expect(t.streamUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    });

    test('drops videos that would show "Video unavailable" or have no timeline', () {
      expect(YouTubeApi.mapVideo(video(embeddable: false)), isNull);
      expect(YouTubeApi.mapVideo(video(live: 'live')), isNull);
      expect(YouTubeApi.mapVideo(video(live: 'upcoming')), isNull);
      expect(YouTubeApi.mapVideo(video(duration: 'P0D')), isNull);
      expect(YouTubeApi.mapVideo(video(id: 'short')), isNull);
    });

    test('parses ISO-8601 durations', () {
      expect(YouTubeApi.parseIsoDuration('PT45S'), 45);
      expect(YouTubeApi.parseIsoDuration('PT1H2M3S'), 3723);
      expect(YouTubeApi.parseIsoDuration('PT10M'), 600);
      expect(YouTubeApi.parseIsoDuration('P1DT2S'), 86402);
      expect(YouTubeApi.parseIsoDuration('garbage'), 0);
    });

    test('decodes entities without double-decoding', () {
      expect(YouTubeApi.decodeEntities('A &amp; B &quot;C&quot;'), 'A & B "C"');
      expect(YouTubeApi.decodeEntities('&amp;#39;'), '&#39;');
    });
  });

  group('RadioBrowserApi.mapStation', () {
    test('maps https stations and skips cleartext ones', () {
      final ok = RadioBrowserApi.mapStation({
        'stationuuid': 'u1',
        'name': ' Radio Mirchi ',
        'url_resolved': 'https://stream.example/live',
        'favicon': 'http://insecure/icon.png',
        'tags': 'bollywood, hindi',
        'country': 'India',
      })!;
      expect(ok.id, 'radio:u1');
      expect(ok.title, 'Radio Mirchi');
      expect(ok.isLive, isTrue);
      expect(ok.artworkUrl, isNull, reason: 'cleartext favicon must be dropped');
      expect(ok.genre, 'bollywood');

      expect(RadioBrowserApi.mapStation({'stationuuid': 'u2', 'url_resolved': 'http://plain/stream'}), isNull);
    });
  });

  group('Track JSON', () {
    test('round-trips through the compact form', () {
      const t = Track(
        id: 'yt:dQw4w9WgXcQ',
        source: TrackSource.youtube,
        title: 'T',
        artist: 'A',
        streamUrl: 'https://s',
        artworkUrl: 'https://art',
        durationMs: 1000,
        genre: 'Pop',
      );
      final back = Track.tryParse(t.toJson())!;
      expect(back, t);
      expect(back.artworkUrl, t.artworkUrl);
      expect(back.durationMs, 1000);
      expect(back.genre, 'Pop');
    });

    test('rejects malformed input and retired sources', () {
      expect(Track.tryParse(null), isNull);
      expect(Track.tryParse(<Object?, Object?>{'id': 'x'}), isNull);
      // Items saved by older builds (Audius) are dropped, not shown as unplayable.
      expect(Track.tryParse(<Object?, Object?>{'id': 'audius:1', 'src': 'audius', 'u': 'https://s'}), isNull);
    });
  });
}
