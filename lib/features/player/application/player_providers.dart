import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../catalog/domain/track.dart';
import '../data/synk_audio_handler.dart';
import 'player_hub.dart';

/// Created by `AudioService.init` in bootstrap and injected via override.
final audioHandlerProvider = Provider<SynkAudioHandler>(
  (ref) => throw UnimplementedError('audioHandlerProvider must be overridden in bootstrap'),
);

/// The app's player: routes radio to background audio and YouTube to the
/// on-screen official player. Everything plays through this.
final playerHubProvider = Provider<PlayerHub>((ref) {
  final hub = PlayerHub(ref.watch(audioHandlerProvider));
  ref.onDispose(hub.dispose);
  return hub;
});

final currentTrackProvider = StreamProvider<Track?>((ref) => ref.watch(playerHubProvider).trackStream);

final _playingProvider = StreamProvider<bool>((ref) => ref.watch(playerHubProvider).playingStream);

final isPlayingProvider = Provider<bool>((ref) => ref.watch(_playingProvider).value ?? false);

/// A few events/sec. Only progress bars should watch this, never whole screens.
final positionProvider = StreamProvider.autoDispose<Duration>((ref) => ref.watch(playerHubProvider).positionStream);

/// Whether a YouTube player is currently on screen (videos can only play then).
final videoVisibleProvider = StreamProvider<bool>((ref) async* {
  final hub = ref.watch(playerHubProvider);
  yield hub.videoVisible;
  yield* hub.videoVisibleStream;
});

/// Whether the floating video player should be up (a video was minimised).
/// The floating card should stand by for the current video (see
/// YouTubeEngine.floatEligible).
final videoFloatEligibleProvider = StreamProvider<bool>((ref) async* {
  final youtube = ref.watch(playerHubProvider).youtube;
  yield youtube.floatEligible;
  yield* youtube.floatEligibleStream;
});

/// A video is meant to be playing (intent, so buffering/handover don't flap it).
final videoWantsPlayProvider = StreamProvider<bool>((ref) async* {
  final youtube = ref.watch(playerHubProvider).youtube;
  yield youtube.wantsPlay;
  yield* youtube.wantsPlayStream;
});

@immutable
class SoloQueue {
  const SoloQueue({this.tracks = const [], this.index = -1});

  final List<Track> tracks;
  final int index;

  Track? get current => index >= 0 && index < tracks.length ? tracks[index] : null;
  bool get hasNext => index + 1 < tracks.length;
  bool get hasPrevious => index > 0;
}

/// Solo listening (outside rooms): a simple local queue.
final soloPlayerProvider = NotifierProvider<SoloPlayerController, SoloQueue>(SoloPlayerController.new);

class SoloPlayerController extends Notifier<SoloQueue> implements TransportDelegate {
  final List<StreamSubscription<Object?>> _subs = [];

  PlayerHub get _handler => ref.read(playerHubProvider);

  @override
  SoloQueue build() {
    bool owns() => identical(_handler.delegate, this);
    _subs.addAll([
      _handler.onCompleted.listen((_) {
        if (owns() && state.hasNext) onNext();
      }),
      // A video that can't be embedded (removed, region-blocked…) → skip it.
      _handler.videoErrors.listen((_) {
        if (owns() && state.hasNext) onNext();
      }),
    ]);
    ref.onDispose(() {
      for (final s in _subs) {
        unawaited(s.cancel());
      }
    });
    return const SoloQueue();
  }

  /// Takes over the audio engine (e.g. after leaving a room).
  void claim() => _handler.delegate = this;

  Future<void> playTracks(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    claim();
    state = SoloQueue(tracks: List.unmodifiable(tracks), index: startIndex);
    await _playCurrent();
  }

  Future<void> playOne(Track track) => playTracks([track]);

  Future<void> _playCurrent() async {
    final track = state.current;
    if (track == null) return;
    await _handler.load(track);
    unawaited(ref.read(localStoreProvider).pushRecentTrack(track.id, track.toJson()));
  }

  Future<void> toggle() => _handler.playing ? onPause() : onPlay();

  /// The current item is a YouTube video (needs its player on screen to play).
  bool get isVideo => state.current?.isYouTube ?? false;

  @override
  Future<void> onPlay() => _handler.playLocal();

  @override
  Future<void> onPause() => _handler.pauseLocal();

  @override
  Future<void> onNext() async {
    if (!state.hasNext) return;
    state = SoloQueue(tracks: state.tracks, index: state.index + 1);
    await _playCurrent();
  }

  @override
  Future<void> onPrevious() async {
    // Standard behaviour: restart the song unless we're in its first 3s.
    if (_handler.position > const Duration(seconds: 3) || !state.hasPrevious) {
      return _handler.seekLocal(Duration.zero);
    }
    state = SoloQueue(tracks: state.tracks, index: state.index - 1);
    await _playCurrent();
  }

  @override
  Future<void> onSeek(Duration position) => _handler.seekLocal(position);

  Future<void> stop() async {
    state = const SoloQueue();
    await _handler.clear();
  }
}
