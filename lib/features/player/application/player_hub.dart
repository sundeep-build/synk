import 'dart:async';

import 'package:youtube_player_iframe/youtube_player_iframe.dart' show YoutubeError;

import '../../catalog/domain/track.dart';
import '../data/media_engine.dart';
import '../data/synk_audio_handler.dart';
import '../data/youtube_engine.dart';

/// The app's single "player": routes each track to the engine for its source
/// (radio → background audio, YouTube → on-screen official player) and exposes
/// one merged set of streams to the UI and controllers.
class PlayerHub {
  PlayerHub(this._audio) : _radio = RadioEngine(_audio) {
    for (final engine in <MediaEngine>[_radio, youtube]) {
      _subs.addAll([
        engine.playingStream.listen((v) {
          if (identical(engine, _active)) _playingCtrl.add(v);
        }),
        engine.positionStream.listen((p) {
          if (identical(engine, _active)) _positionCtrl.add(p);
        }),
        engine.completedStream.listen((_) {
          if (identical(engine, _active)) _completedCtrl.add(null);
        }),
      ]);
    }
  }

  final SynkAudioHandler _audio;
  final RadioEngine _radio;
  final YouTubeEngine youtube = YouTubeEngine();
  final List<StreamSubscription<Object?>> _subs = [];

  final StreamController<Track?> _trackCtrl = StreamController.broadcast();
  final StreamController<bool> _playingCtrl = StreamController.broadcast();
  final StreamController<Duration> _positionCtrl = StreamController.broadcast();
  final StreamController<void> _completedCtrl = StreamController.broadcast();

  Track? _current;

  MediaEngine get _active => (_current?.isYouTube ?? false) ? youtube : _radio;

  /// Lock-screen / headset buttons (radio only; YouTube has no background).
  TransportDelegate? get delegate => _audio.delegate;
  set delegate(TransportDelegate? value) => _audio.delegate = value;

  Track? get current => _current;
  bool get playing => _active.playing;
  bool get isBuffering => _active.isBuffering;
  double get speed => _active.speed;
  Duration get position => _active.position;

  /// YouTube only supports coarse playback rates (0.25x steps), so rooms use
  /// seek-only drift correction for videos. (Live radio is never corrected.)
  bool get supportsRateNudge => !(_current?.isYouTube ?? false);

  /// A YouTube player is on screen (only then can a video actually play).
  bool get videoVisible => youtube.visible;
  Stream<bool> get videoVisibleStream => youtube.visibleStream;
  Stream<YoutubeError> get videoErrors => youtube.errorStream;

  Stream<Track?> get trackStream async* {
    yield _current;
    yield* _trackCtrl.stream;
  }

  Stream<bool> get playingStream async* {
    yield playing;
    yield* _playingCtrl.stream;
  }

  Stream<Duration> get positionStream => _positionCtrl.stream;
  Stream<void> get onCompleted => _completedCtrl.stream;

  Future<void> load(Track track, {Duration position = Duration.zero, bool play = true}) async {
    final next = track.isYouTube ? youtube : _radio;
    // Only one source plays at a time: switching engines stops the other one
    // (this also removes the radio notification when a video starts).
    if (_current != null && !identical(next, _active)) await _active.clear();
    _current = track;
    _trackCtrl.add(track);
    await next.load(track, position: position, play: play);
  }

  Future<void> playLocal() => _active.play();
  Future<void> pauseLocal() => _active.pause();
  Future<void> seekLocal(Duration position) => _active.seek(position);
  Future<void> setSpeedLocal(double speed) => _active.setSpeed(speed);

  Future<void> clear() async {
    await _active.clear();
    _current = null;
    _trackCtrl.add(null);
    _playingCtrl.add(false);
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await youtube.dispose();
    await Future.wait([_trackCtrl.close(), _playingCtrl.close(), _positionCtrl.close(), _completedCtrl.close()]);
  }
}
