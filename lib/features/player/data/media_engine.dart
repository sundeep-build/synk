import 'dart:async';

import '../../catalog/domain/track.dart';
import 'synk_audio_handler.dart';

/// A playback backend. [PlayerHub] routes each track to the engine for its
/// source, so controllers (solo queue, rooms) are source-agnostic.
abstract interface class MediaEngine {
  Future<void> load(Track track, {Duration position = Duration.zero, bool play = true});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);

  /// Stops playback and forgets the current item.
  Future<void> clear();

  bool get playing;
  bool get isBuffering;
  double get speed;
  Duration get position;

  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<void> get completedStream;
}

/// Live radio through just_audio + audio_service: background playback,
/// notification and lock-screen controls.
class RadioEngine implements MediaEngine {
  RadioEngine(this._handler);

  final SynkAudioHandler _handler;

  @override
  Future<void> load(Track track, {Duration position = Duration.zero, bool play = true}) =>
      _handler.load(track, position: position, play: play);

  @override
  Future<void> play() => _handler.playLocal();

  @override
  Future<void> pause() => _handler.pauseLocal();

  @override
  Future<void> seek(Duration position) => _handler.seekLocal(position);

  @override
  Future<void> setSpeed(double speed) => _handler.setSpeedLocal(speed);

  @override
  Future<void> clear() => _handler.clear();

  @override
  bool get playing => _handler.playing;

  @override
  bool get isBuffering => _handler.isBuffering;

  @override
  double get speed => _handler.speed;

  @override
  Duration get position => _handler.position;

  @override
  Stream<bool> get playingStream => _handler.playerStateStream.map((s) => s.playing).distinct();

  @override
  Stream<Duration> get positionStream => _handler.positionStream;

  @override
  Stream<void> get completedStream => _handler.onCompleted;
}
