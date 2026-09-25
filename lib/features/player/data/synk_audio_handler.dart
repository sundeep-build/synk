import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/logging/app_logger.dart';
import '../../catalog/domain/track.dart';

/// Whoever currently "owns" playback (solo queue or a room session) decides
/// what lock-screen / headset buttons do. In a room, "next" means
/// "vote to skip", and only the host's pause pauses everyone.
abstract interface class TransportDelegate {
  Future<void> onPlay();
  Future<void> onPause();
  Future<void> onNext();
  Future<void> onPrevious();
  Future<void> onSeek(Duration position);
}

/// One audio engine for the whole app, running inside audio_service so it
/// survives backgrounding and shows system media controls — the #1 thing
/// Groic users asked for.
///
/// Controllers call the `*Local` methods to drive the engine directly; system
/// transport events go through [delegate].
class SynkAudioHandler extends BaseAudioHandler with SeekHandler {
  SynkAudioHandler() {
    _eventSub = _player.playbackEventStream.listen(
      (_) => _broadcast(),
      onError: (Object e, StackTrace st) => AppLogger.error('Audio', e, st),
    );
    _stateSub = _player.playerStateStream.listen((s) {
      _broadcast();
      if (s.processingState == ProcessingState.completed) _completed.add(null);
    });
  }

  // Send the user agent natively (ExoPlayer/AVPlayer). The default would route every
  // stream through just_audio's local http://127.0.0.1 proxy, which Android blocks as
  // cleartext traffic, so nothing would play.
  final AudioPlayer _player = AudioPlayer(userAgent: 'Synk/1.0', useProxyForRequestHeaders: false);
  final StreamController<void> _completed = StreamController.broadcast();
  final StreamController<Track?> _trackCtrl = StreamController.broadcast();
  late final StreamSubscription<PlaybackEvent> _eventSub;
  late final StreamSubscription<PlayerState> _stateSub;

  TransportDelegate? delegate;
  Track? _current;

  Track? get current => _current;
  bool get playing => _player.playing;
  double get speed => _player.speed;
  Duration get position => _player.position;
  bool get isBuffering =>
      _player.processingState == ProcessingState.loading || _player.processingState == ProcessingState.buffering;

  Stream<void> get onCompleted => _completed.stream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// Emits the current track immediately, then every change.
  Stream<Track?> get trackStream async* {
    yield _current;
    yield* _trackCtrl.stream;
  }

  /// Loads [track] and (optionally) starts playing from [position].
  Future<void> load(Track track, {Duration position = Duration.zero, bool play = true}) async {
    _current = track;
    _trackCtrl.add(track);
    mediaItem.add(
      MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artist,
        genre: track.genre,
        duration: track.isLive || track.durationMs == 0 ? null : track.duration,
        artUri: track.artworkUrl == null ? null : Uri.tryParse(track.artworkUrl!),
        extras: {'live': track.isLive},
      ),
    );
    try {
      await _player.setSpeed(1);
      await _player.setAudioSource(
        AudioSource.uri(Uri.parse(track.streamUrl)),
        initialPosition: track.isLive ? null : position,
      );
      // play() completes only when playback stops — never await it.
      if (play) unawaited(_player.play());
    } on PlayerException catch (e, st) {
      AppLogger.error('Audio', e, st);
      rethrow;
    } on PlayerInterruptedException {
      // A newer load() replaced this one; nothing to do.
    }
  }

  Future<void> playLocal() async => unawaited(_player.play());
  Future<void> pauseLocal() => _player.pause();
  Future<void> seekLocal(Duration position) => _player.seek(position);
  Future<void> setSpeedLocal(double speed) => _player.setSpeed(speed);

  Future<void> clear() async {
    await _player.stop();
    _current = null;
    _trackCtrl.add(null);
    mediaItem.add(null);
  }

  // ── System transport (lock screen, notification, headset) ─────────────────
  @override
  Future<void> play() => delegate?.onPlay() ?? playLocal();

  @override
  Future<void> pause() => delegate?.onPause() ?? pauseLocal();

  @override
  Future<void> seek(Duration position) => delegate?.onSeek(position) ?? seekLocal(position);

  @override
  Future<void> skipToNext() => delegate?.onNext() ?? Future.value();

  @override
  Future<void> skipToPrevious() => delegate?.onPrevious() ?? Future.value();

  @override
  Future<void> stop() async {
    await clear();
    await super.stop();
  }

  void _broadcast() {
    final live = _current?.isLive ?? false;
    final isPlaying = _player.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          if (!live) MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: live ? const {} : const {MediaAction.seek},
        androidCompactActionIndices: live ? const [0, 1] : const [0, 1, 2],
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: isPlaying,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ),
    );
  }

  Future<void> dispose() async {
    await _eventSub.cancel();
    await _stateSub.cancel();
    await _completed.close();
    await _trackCtrl.close();
    await _player.dispose();
  }
}
