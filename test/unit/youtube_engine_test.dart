import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synk/features/catalog/domain/track.dart';
import 'package:synk/features/player/data/youtube_engine.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// A player that accepts every command at once and records it.
class _Recorder implements YoutubePlayerController {
  final calls = <Symbol>[];

  @override
  Object? noSuchMethod(Invocation i) {
    if (i.memberName == #listen) return const Stream<YoutubePlayerValue>.empty().listen(null);
    if (i.memberName == #videoStateStream) return const Stream<YoutubeVideoState>.empty();
    calls.add(i.memberName);
    return Future<void>.value();
  }
}

/// A player whose YouTube page never becomes ready: every command times out,
/// like the package does after 30 s.
class _NeverReady implements YoutubePlayerController {
  final calls = <Symbol>[];

  @override
  Object? noSuchMethod(Invocation i) {
    if (i.memberName == #listen) return const Stream<YoutubePlayerValue>.empty().listen(null);
    if (i.memberName == #videoStateStream) return const Stream<YoutubeVideoState>.empty();
    calls.add(i.memberName);
    return Future<void>.error(TimeoutException('YouTube player failed to initialize within 30 seconds.'));
  }
}

const _video = Track(
  id: 'yt:dQw4w9WgXcQ',
  source: TrackSource.youtube,
  title: 'Video',
  artist: 'Artist',
  streamUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
  durationMs: 180000,
);

void main() {
  late YouTubeEngine engine;

  // The timeout tests log "player not ready" on purpose; keep test output clean.
  final print = debugPrint;
  setUp(() {
    engine = YouTubeEngine();
    debugPrint = (_, {wrapWidth}) {};
  });
  tearDown(() {
    debugPrint = print;
    return engine.dispose();
  });

  test('a playing video with no full-size player on screen goes floating', () async {
    await engine.load(_video);
    expect(engine.wantsFloating, isTrue);
  });

  test('a full-size player (room / Now Playing) takes it back, minimising returns it', () async {
    await engine.load(_video);
    engine.addPrimaryStage();
    expect(engine.wantsFloating, isFalse);
    engine.removePrimaryStage();
    expect(engine.wantsFloating, isTrue);
  });

  test('a pause keeps the card up; ✕ puts it away; playing again brings it back', () async {
    await engine.load(_video);
    await engine.pause();
    expect(engine.wantsFloating, isTrue, reason: 'paused in place, no reload');
    engine.dismissFloating();
    expect(engine.wantsFloating, isFalse);
    await engine.play();
    expect(engine.wantsFloating, isTrue);
    await engine.clear();
    expect(engine.wantsFloating, isFalse);
  });

  test('minimising an already-paused video does not pop up a card', () async {
    await engine.load(_video);
    engine.addPrimaryStage();
    await engine.pause();
    engine.removePrimaryStage();
    expect(engine.wantsFloating, isFalse);
  });

  test('the floating card stands by while the room plays a video, so it can take it over mid-play', () async {
    await engine.load(_video);
    engine.addPrimaryStage(); // the room is open
    expect(engine.wantsFloating, isFalse, reason: 'not shown while the room shows it');
    expect(engine.floatEligible, isTrue, reason: 'but ready to take over');
    await engine.pause();
    expect(engine.floatEligible, isFalse, reason: 'minimising a paused video pops nothing up');
    await engine.play();
    engine.removePrimaryStage(); // minimised: floating now
    await engine.pause();
    expect(engine.floatEligible, isTrue, reason: 'a pause keeps the card');
    engine.dismissFloating();
    expect(engine.floatEligible, isFalse, reason: '✕ lets it go');
    await engine.play();
    await engine.clear();
    expect(engine.floatEligible, isFalse);
  });

  test('play intent (arms PiP) follows play/pause, not buffering', () async {
    expect(engine.wantsPlay, isFalse);
    await engine.load(_video);
    expect(engine.wantsPlay, isTrue);
    await engine.pause();
    expect(engine.wantsPlay, isFalse);
    await engine.play();
    expect(engine.wantsPlay, isTrue);
    await engine.clear();
    expect(engine.wantsPlay, isFalse);
  });

  test('a video loaded paused never floats', () async {
    await engine.load(_video, play: false);
    expect(engine.wantsFloating, isFalse);
  });

  test('changes are announced asynchronously (safe while widgets mount mid-frame)', () async {
    await engine.load(_video);
    final events = <bool>[];
    final sub = engine.floatingStream.listen(events.add);
    engine
      ..addPrimaryStage()
      ..removePrimaryStage()
      ..addPrimaryStage();
    expect(events, isEmpty, reason: 'nothing delivered synchronously');
    await Future<void>.delayed(Duration.zero);
    expect(events, [false, true, false]);
    await sub.cancel();
  });

  test('a stuck live stage retries loading once; a closed one is left alone', () async {
    final live = _NeverReady();
    engine.attach(live);
    await engine.load(_video);
    await pumpEventQueue();
    expect(live.calls.where((c) => c == #loadVideoById), hasLength(2), reason: 'first try + one retry');

    final gone = _NeverReady();
    engine
      ..attach(gone)
      ..detach(gone); // e.g. floating player closed before YouTube loaded
    await pumpEventQueue();
    expect(gone.calls.where((c) => c == #loadVideoById), hasLength(1), reason: 'no retry for a removed stage');
  });

  test('a stage mounting under the PiP window parks instead of taking the video', () async {
    await engine.load(_video);
    final pip = _Recorder();
    engine.attach(pip, pinned: true);
    await pumpEventQueue();
    pip.calls.clear();

    final underneath = _Recorder(); // e.g. floating card remounting in the offstage app
    engine.attach(underneath);
    await pumpEventQueue();
    expect(underneath.calls, isEmpty, reason: 'parked: not cued, not playing');
    expect(pip.calls, isNot(contains(#pauseVideo)), reason: 'PiP keeps playing');

    engine.detach(pip); // PiP window expanded back into the app
    await pumpEventQueue();
    expect(underneath.calls, contains(#loadVideoById), reason: 'takes over where the video is');
  });
}
