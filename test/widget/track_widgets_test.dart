import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synk/core/design_system/design_system.dart';
import 'package:synk/features/catalog/domain/track.dart';
import 'package:synk/features/catalog/presentation/track_widgets.dart';
import 'package:synk/features/player/application/player_providers.dart';
import 'package:synk/features/player/presentation/player_progress.dart';

const _song = Track(
  id: 'yt:abcdefghijk',
  source: TrackSource.youtube,
  title: 'A very long song title that just keeps on going',
  artist: 'Some Artist With A Long Name',
  streamUrl: '',
  durationMs: 100000,
);

const _station = Track(
  id: 'radio:1',
  source: TrackSource.radio,
  title: 'Radio Mirchi 98.3 FM Punjab Live',
  artist: 'India',
  streamUrl: '',
  genre: 'Bollywood',
);

Widget _host(Widget child, {Track? current, bool playing = false, Duration position = Duration.zero}) => ProviderScope(
  overrides: [
    currentTrackProvider.overrideWith((ref) => Stream.value(current)),
    isPlayingProvider.overrideWithValue(playing),
    positionProvider.overrideWith((ref) => Stream.value(position)),
  ],
  retry: (_, _) => null,
  child: MediaQuery(
    data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(1.35)),
    child: MaterialApp(
      theme: ThemeData(brightness: Brightness.dark, extensions: const [SynkColors.dark]),
      home: Scaffold(body: child),
    ),
  ),
);

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(360, 800);
    view.devicePixelRatio = 1;
  });
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.reset());

  testWidgets('track rows fit a 360dp phone at the largest text size; tap plays', (tester) async {
    var played = 0;
    await tester.pumpWidget(_host(TrackListView(tracks: const [_song, _station], onTap: (_) => played++)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('1:40'), findsOneWidget, reason: 'duration shown for songs');
    await tester.tap(find.bySemanticsLabel('Play').first);
    expect(played, 1);
  });

  testWidgets('the playing row shows Pause', (tester) async {
    await tester.pumpWidget(
      _host(
        TrackTile(track: _song, onTap: () {}),
        current: _song,
        playing: true,
      ),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
  });

  testWidgets('station card fits its rail and says Playing when it is', (tester) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => SizedBox(
            height: TrackCard.railHeight(context),
            child: TrackCard(track: _station, onTap: () {}),
          ),
        ),
        current: _station,
        playing: true,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Playing'), findsOneWidget);
  });

  testWidgets('tapping the waveform seeks to that spot', (tester) async {
    Duration? seekedTo;
    await tester.pumpWidget(
      _host(
        Padding(
          padding: const EdgeInsets.all(20),
          child: PlayerProgress(track: _song, waveform: true, onSeek: (d) => seekedTo = d),
        ),
        position: const Duration(seconds: 10),
      ),
    );
    await tester.pump();
    expect(find.text('0:10'), findsOneWidget);
    final bar = tester.getRect(find.byType(CustomPaint).last);
    await tester.tapAt(Offset(bar.left + bar.width / 2, bar.center.dy));
    await tester.pump();
    expect(seekedTo?.inSeconds, inInclusiveRange(49, 51));
  });
}
