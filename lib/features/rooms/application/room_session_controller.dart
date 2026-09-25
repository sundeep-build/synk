import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/logging/app_logger.dart';
import '../../auth/application/session.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/domain/track.dart';
import '../../player/application/player_hub.dart';
import '../../player/application/player_providers.dart';
import '../../player/data/synk_audio_handler.dart';
import '../../profile/domain/user_profile.dart';
import '../data/room_live_datasource.dart';
import '../data/room_repository.dart';
import '../domain/room.dart';
import '../domain/room_live_models.dart';
import '../domain/room_playback.dart';
import '../sync/drift_corrector.dart';
import '../sync/room_rules.dart';
import '../sync/server_clock.dart';
import 'room_providers.dart';
import 'room_session.dart';

/// The one room the user is in (or null). Kept alive app-wide so the music
/// keeps playing while the user browses other tabs or locks the phone.
final roomSessionProvider = NotifierProvider<RoomSessionController, RoomSession?>(RoomSessionController.new);

/// Orchestrates a room session:
/// * presence (join/leave with server-side disconnect cleanup)
/// * applying the shared playback anchor to the local player + drift loop
/// * race-free auto-advance (queue → autoplay similar) via RTDB transactions
/// * skip votes, host transport, chat/reactions/dedications
/// * directory heartbeat (leader only)
class RoomSessionController extends Notifier<RoomSession?> implements TransportDelegate {
  static const _drift = DriftCorrector();

  final List<StreamSubscription<Object?>> _subs = [];
  final Random _random = Random();
  final List<String> _recentlyPlayed = [];

  /// Every queue entry seen this session (insertion-ordered, capped), so the
  /// Now playing row can still say who queued a track after its entry is
  /// deleted from the live queue.
  final Map<String, QueueItem> _knownItems = {};
  Timer? _syncTimer;
  Timer? _heartbeatTimer;
  Timer? _beatDebounce;
  Timer? _advanceTimer;
  int? _loadedSeq;
  int? _advanceArmedFor;

  /// The seq whose advance found nothing to play: no more retries until
  /// someone queues a song.
  int? _stuckOn;
  String? _cleanedQueueItem;
  ({int count, String? trackId})? _lastBeat;
  DateTime _lastBeatAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastDriftSeek = DateTime.fromMillisecondsSinceEpoch(0);
  bool _joining = false;
  bool _restoringPresence = false;

  PlayerHub get _audio => ref.read(playerHubProvider);
  RoomLiveDataSource get _live => ref.read(roomLiveProvider);
  RoomRepository get _rooms => ref.read(roomRepositoryProvider);
  ServerClock get _clock => ref.read(serverClockProvider);

  UserProfile get _me {
    final me = ref.read(currentProfileProvider);
    if (me == null) throw const AuthException('Finish setting up your profile first.');
    return me;
  }

  @override
  RoomSession? build() {
    ref.onDispose(_teardown);
    return null;
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────
  Future<void> join(String roomId) async {
    final me = _me;
    if (state?.room.id == roomId && !(state?.ended ?? false)) return;
    if (_joining) return;
    _joining = true;
    try {
      if (state != null) await leave();
      // Start measuring the server clock offset now, so it's known before
      // the first playback anchor arrives.
      ref.read(serverClockProvider);
      final room = await _rooms.get(roomId);
      final isHost = room.hostId == me.uid;
      if (room.closed) throw const NotFoundException(message: 'This room has ended.');
      // Everyone left: only its host can bring it back.
      if (!room.isLive && !isHost) {
        throw const NotFoundException(message: 'This room is paused until its host is back.');
      }
      if (!isHost && !await _live.isMember(roomId, me.uid)) {
        if (await _live.memberCount(roomId) >= room.capacity) throw const RoomFullException();
      }

      await _live.join(roomId, me);
      state = RoomSession(room: room, myUid: me.uid);
      if (isHost) ref.invalidate(myRoomsProvider);
      _audio.delegate = this;
      _subscribe(roomId);
      _syncTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) => _maybeHeartbeat());

      unawaited(
        ref
            .read(analyticsProvider)
            .logEvent(name: 'room_join', parameters: {'mode': room.mode.name, 'is_host': isHost ? 1 : 0}),
      );
    } catch (e) {
      throw AppException.from(e);
    } finally {
      _joining = false;
    }
  }

  /// Leaves the room. The host can [endForAll] to close it for everyone.
  Future<void> leave({bool endForAll = false}) async {
    final s = state;
    if (s == null) return;
    _teardown();
    state = null;
    // Stop the room's audio/video now, while its screen is still up — before
    // any network wait. Otherwise the room's player unmounts first and the
    // floating player picks the video back up after the user has left.
    final handBack = _handBackAudio();
    try {
      if (!s.ended) await _live.leave(s.room.id, s.myUid);
      if (endForAll && s.isHost) {
        await _rooms.close(s.room.id);
      } else if (!s.ended && s.members.every((m) => m.uid == s.myUid)) {
        await _rooms.markIdle(s.room.id);
      }
    } catch (e, st) {
      AppLogger.error('RoomLeave', e, st);
    }
    if (s.isHost) ref.invalidate(myRoomsProvider);
    await handBack;
  }

  /// Clears an "ended" session after the UI has shown it.
  void dismissEnded() {
    if (state?.ended ?? false) state = null;
  }

  void _subscribe(String roomId) {
    void onError(Object e, StackTrace st) => AppLogger.error('RoomStream', e, st);
    _subs.addAll([
      _live.meta(roomId).listen(_onMeta, onError: onError),
      _live.playback(roomId).listen(_onPlayback, onError: onError),
      _live.queue(roomId).listen(_onQueue, onError: onError),
      _live.members(roomId).listen(_onMembers, onError: onError),
      _live.skipVotes(roomId).listen((v) => _update((s) => s.copyWith(skipVotes: v)), onError: onError),
      // A YouTube player came on screen (room opened / app resumed): jump to
      // where the room is now. Videos can't play while off screen.
      _audio.videoVisibleStream.listen((visible) {
        final p = state?.playback;
        if (visible && p != null && (p.track?.isYouTube ?? false)) {
          _loadedSeq = null;
          unawaited(_apply(p));
        }
      }),
      // Unplayable video (removed / not embeddable): whoever controls moves on.
      _audio.videoErrors.listen((_) {
        final s = state;
        if (s != null && s.canControl && s.playback.track != null) _armAdvance(s.playback.seq, immediate: true);
      }),
      // Local "ended" is a fallback for tracks whose duration we don't know.
      _audio.onCompleted.listen((_) {
        final s = state;
        if (s != null && s.playback.track != null && s.playback.track!.durationMs <= 0) _armAdvance(s.playback.seq);
      }),
    ]);
  }

  void _teardown() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    for (final t in [_syncTimer, _heartbeatTimer, _beatDebounce, _advanceTimer]) {
      t?.cancel();
    }
    _loadedSeq = null;
    _advanceArmedFor = null;
    _stuckOn = null;
    _cleanedQueueItem = null;
    _lastBeat = null;
    _knownItems.clear();
  }

  Future<void> _handBackAudio() async {
    final solo = ref.read(soloPlayerProvider.notifier)..claim();
    await solo.stop();
  }

  void _update(RoomSession Function(RoomSession s) change) {
    final s = state;
    if (s != null && !s.ended) state = change(s);
  }

  // ── Remote state → local player ──────────────────────────────────────────
  void _onMeta(RoomMeta? meta) {
    final s = state;
    if (s == null || !(meta?.closed ?? false) || s.isHost) return;
    _teardown();
    state = s.copyWith(ended: true);
    unawaited(_live.leave(s.room.id, s.myUid).catchError((Object _) {}));
    unawaited(_handBackAudio());
  }

  void _onMembers(List<RoomMember> members) {
    _update((s) => s.copyWith(members: members));
    final s = state;
    if (s != null && !s.ended && !members.any((m) => m.uid == s.myUid)) unawaited(_restorePresence(s));
    _maybeHeartbeat();
  }

  /// A dropped connection (screen off, Wi-Fi ↔ mobile data) fires our
  /// disconnect cleanup on the server, which takes us out of the room while
  /// the app is still in it. Others' counts then miss us, and every rule that
  /// needs us in the room (chat, queue, reactions, huddle) refuses us. Nothing
  /// else puts us back, so announce ourselves again.
  Future<void> _restorePresence(RoomSession s) async {
    if (_restoringPresence) return;
    _restoringPresence = true;
    final roomId = s.room.id;
    try {
      await _live.join(roomId, _me);
      final cur = state;
      if (cur == null || cur.ended || cur.room.id != roomId) {
        // Left while this was in flight: don't leave a ghost behind.
        await _live.leave(roomId, s.myUid);
        return;
      }
      _update((cur) => cur.copyWith(rejoins: cur.rejoins + 1));
    } catch (e, st) {
      // Room ended meanwhile (_onMeta handles it), or offline: the next
      // members update tries again.
      AppLogger.error('RoomPresence', e, st);
    } finally {
      _restoringPresence = false;
    }
  }

  void _onQueue(List<QueueItem> queue) {
    for (final item in queue) {
      _knownItems[item.id] = item;
    }
    while (_knownItems.length > AppConfig.maxQueueLength * 3) {
      _knownItems.remove(_knownItems.keys.first);
    }
    _update((s) {
      final qid = s.playback.queueItemId;
      final resolve = qid != null && s.playingItem?.id != qid && _knownItems.containsKey(qid);
      return s.copyWith(queue: queue, playingItem: resolve ? () => _knownItems[qid] : null);
    });
    // Someone queued a song while the room had run out: try again now.
    if (_stuckOn != null && (state?.upcoming.isNotEmpty ?? false)) {
      if (_advanceArmedFor == _stuckOn) _advanceArmedFor = null;
      _stuckOn = null;
    }
  }

  void _onPlayback(RoomPlayback p) {
    final previous = state?.playback;
    _update((s) => s.withPlayback(p, _knownItems));
    if (previous?.seq != p.seq) {
      _advanceTimer?.cancel();
      _advanceArmedFor = null;
    }
    unawaited(_apply(p));
    if (previous?.track?.id != p.track?.id) _maybeHeartbeat(force: true);
  }

  Future<void> _apply(RoomPlayback p) async {
    final s = state;
    if (s == null || s.locallyPaused) return;
    final track = p.track;
    // Nothing on, or we joined after this song finished and the room is
    // waiting for the next one. (Loading a video at its last second fails
    // with "invalid parameter" and leaves a black player.)
    if (track == null || p.hasEnded(_clock.nowMs())) {
      if (_audio.playing) await _audio.pauseLocal();
      return;
    }
    final expected = Duration(milliseconds: p.expectedPositionMs(_clock.nowMs()));
    try {
      if (_loadedSeq != p.seq || _audio.current?.id != track.id) {
        _loadedSeq = p.seq;
        _remember(track.id);
        await _audio.load(track, position: expected, play: p.isPlaying);
        unawaited(ref.read(localStoreProvider).pushRecentTrack(track.id, track.toJson()));
        return;
      }
      if (p.isPlaying && !_audio.playing) {
        if (!track.isLive) await _audio.seekLocal(expected);
        await _audio.playLocal();
      } else if (!p.isPlaying && _audio.playing) {
        await _audio.pauseLocal();
        if (!track.isLive) await _audio.seekLocal(Duration(milliseconds: p.positionMs));
      } else {
        _correctDrift(p); // e.g. host seeked while playing
      }
    } catch (e, st) {
      AppLogger.error('RoomSync', e, st);
      // Unplayable stream: whoever controls the room moves on.
      if (state?.canControl ?? false) _armAdvance(p.seq, immediate: true);
    }
  }

  void _tick() {
    final s = state;
    if (s == null || s.ended) return;
    final p = s.playback;

    if (!s.locallyPaused) _correctDrift(p);

    final idleWithQueue = p.track == null && s.upcoming.isNotEmpty;
    final ended = p.hasEnded(_clock.nowMs());
    if (ended != s.songEnded) _update((cur) => cur.copyWith(songEnded: ended));
    final votedOut = p.track != null && s.members.length > 1 && s.skipVotesForCurrent >= s.skipThreshold;
    if (idleWithQueue || ended || votedOut) _armAdvance(p.seq);

    // Consumed queue entry left behind by a crashed writer → tidy it.
    final qid = p.queueItemId;
    if (s.isLeader && qid != null && qid != _cleanedQueueItem && s.queue.any((q) => q.id == qid)) {
      _cleanedQueueItem = qid;
      unawaited(_live.removeFromQueue(s.room.id, qid).catchError((Object _) {}));
    }
  }

  void _correctDrift(RoomPlayback p) {
    final track = p.track;
    if (track == null || !p.isPlaying || _audio.current?.id != track.id || !_audio.playing || _audio.isBuffering) {
      return;
    }
    final action = _drift.decide(
      expectedMs: p.expectedPositionMs(_clock.nowMs()),
      actualMs: _audio.position.inMilliseconds,
      currentSpeed: _audio.speed,
      isLive: track.isLive,
      allowRate: _audio.supportsRateNudge,
    );
    switch (action) {
      case SyncSeek(:final positionMs):
        // Don't hammer the YouTube player (e.g. while an ad plays, its clock stands still).
        final now = DateTime.now();
        if (now.difference(_lastDriftSeek) < const Duration(seconds: 5)) return;
        _lastDriftSeek = now;
        unawaited(_audio.seekLocal(Duration(milliseconds: positionMs)));
      case SyncRate(:final speed):
        unawaited(_audio.setSpeedLocal(speed));
      case SyncHold():
        break;
    }
  }

  // ── Advancing tracks ─────────────────────────────────────────────────────
  void _armAdvance(int fromSeq, {bool immediate = false}) {
    final s = state;
    if (s == null || _advanceArmedFor == fromSeq) return;
    _advanceArmedFor = fromSeq;
    final delay = immediate
        ? Duration.zero
        : RoomRules.advanceDelay(isLeader: s.isLeader, jitterMs: _random.nextInt(1500));
    _advanceTimer?.cancel();
    _advanceTimer = Timer(delay, () => unawaited(_advance(fromSeq)));
  }

  /// Moves the room on from [fromSeq]: to [pick] (a queue entry), to
  /// [explicit] (a track from outside the queue), or else to the head of the
  /// queue, falling back to autoplay.
  Future<void> _advance(int fromSeq, {Track? explicit, QueueItem? pick}) async {
    final s = state;
    if (s == null || s.playback.seq != fromSeq) return;
    try {
      final head = pick ?? (explicit == null ? s.upcoming.firstOrNull : null);
      var next = explicit ?? head?.track;
      if (next == null) {
        if (s.room.mode != RoomMode.radio) next = await _autoplayPick(s);
        if (state?.playback.seq != fromSeq) return;
        if (next == null) {
          // Nothing to play until someone adds a song (_onQueue retries).
          _stuckOn = fromSeq;
          return;
        }
      }
      final won = await _live.advance(s.room.id, fromSeq: fromSeq, next: next, by: s.myUid, queueItemId: head?.id);
      if (won && head != null) await _live.removeFromQueue(s.room.id, head.id);
    } catch (e, st) {
      AppLogger.error('RoomAdvance', e, st);
      // Back off before the tick loop may try again.
      Timer(const Duration(seconds: 5), () {
        if (_advanceArmedFor == fromSeq) _advanceArmedFor = null;
      });
    }
  }

  /// Next song when the queue is empty: a similar trending one, or, when
  /// those can't be fetched (no YouTube key in this build, daily quota used
  /// up), one the room already played. Network errors still throw (retried).
  Future<Track?> _autoplayPick(RoomSession s) async {
    try {
      final similar = await ref
          .read(catalogRepositoryProvider)
          .nextSimilar(s.playback.track, regionCode: ref.read(regionCodeProvider), exclude: _recentlyPlayed.toSet());
      if (similar != null) return similar;
    } on YouTubeNotConfiguredException {
      // Radio-only build: fall through to replaying.
    } on ServiceUnavailableException catch (e) {
      AppLogger.info('RoomAdvance', 'autoplay unavailable: ${e.message}');
    }
    return RoomRules.replayCandidate(s.played, currentId: s.playback.track?.id);
  }

  void _remember(String trackId) {
    _recentlyPlayed
      ..remove(trackId)
      ..add(trackId);
    if (_recentlyPlayed.length > 30) _recentlyPlayed.removeAt(0);
  }

  // ── Directory heartbeat (leader only) ────────────────────────────────────
  void _maybeHeartbeat({bool force = false}) {
    final s = state;
    if (s == null || s.ended || !s.isLeader) return;
    final signature = (count: s.members.length, trackId: s.playback.track?.id);
    final due = DateTime.now().difference(_lastBeatAt) >= AppConfig.roomHeartbeat;
    if (!force && !due && signature == _lastBeat) return;

    // Debounce bursts (several people joining at once = one write).
    _beatDebounce?.cancel();
    _beatDebounce = Timer(const Duration(seconds: 2), () async {
      final cur = state;
      if (cur == null || cur.ended || !cur.isLeader) return;
      final t = cur.playback.track;
      _lastBeat = (count: cur.members.length, trackId: t?.id);
      _lastBeatAt = DateTime.now();
      try {
        await _rooms.heartbeat(
          cur.room.id,
          listenerCount: cur.members.length,
          nowPlaying: t == null ? null : NowPlayingSummary(title: t.title, artist: t.artist, artworkUrl: t.artworkUrl),
        );
      } catch (e, st) {
        AppLogger.error('RoomHeartbeat', e, st);
      }
    });
  }

  // ── User actions ─────────────────────────────────────────────────────────
  /// Host: play immediately. Everyone else: add to the queue.
  Future<void> playOrQueue(Track track) async {
    final s = state;
    if (s == null) return;
    // Nothing playing (or the last song ended): a controller's pick plays now.
    if (s.canControl && (s.room.mode == RoomMode.radio || s.playback.track == null || s.songEnded)) {
      // Already queued → play that entry, so it isn't played a second time later.
      final queued = s.upcoming.where((q) => q.track.id == track.id).firstOrNull;
      await _advance(s.playback.seq, explicit: queued == null ? track : null, pick: queued);
    } else {
      await addToQueue(track);
    }
  }

  Future<void> addToQueue(Track track) async {
    final s = state;
    if (s == null) return;
    if (s.upcoming.length >= AppConfig.maxQueueLength) {
      throw const ValidationException('The queue is full.');
    }
    if (s.upcoming.any((q) => q.track.id == track.id)) {
      throw const ValidationException('Already in the queue.');
    }
    if (s.playback.track?.id == track.id) {
      throw const ValidationException("That's playing right now.");
    }
    await _live.addToQueue(s.room.id, _me, track);
  }

  Future<void> removeFromQueue(QueueItem item) async {
    final s = state;
    if (s == null || !(s.canControl || item.addedBy == s.myUid)) return;
    await _live.removeFromQueue(s.room.id, item.id);
  }

  /// Controllers: jump straight to a queued track.
  Future<void> playNow(QueueItem item) async {
    final s = state;
    if (s == null || !s.canControl || !s.upcoming.contains(item)) return;
    _advanceTimer?.cancel();
    _advanceArmedFor = s.playback.seq;
    await _advance(s.playback.seq, pick: item);
  }

  /// Controllers skip instantly; everyone else casts a vote.
  Future<void> skip() async {
    final s = state;
    if (s == null || s.playback.track == null) return;
    if (s.canControl) {
      _advanceTimer?.cancel();
      _advanceArmedFor = s.playback.seq;
      await _advance(s.playback.seq);
    } else if (!s.iVotedSkip) {
      await _live.voteSkip(s.room.id, s.myUid, s.playback.seq);
    }
  }

  Future<void> togglePlay() => _audio.playing ? onPause() : onPlay();

  /// Stop hearing/watching on this device only — the room keeps playing for
  /// everyone else, even when the host does this. [onPlay] rejoins.
  Future<void> muteLocally() async {
    if (state == null) return;
    _update((s) => s.copyWith(locallyPaused: true));
    await _audio.pauseLocal();
  }

  Future<void> sendMessage(String text) async {
    final s = state;
    final body = text.trim();
    if (s == null || body.isEmpty) return;
    await _live.sendMessage(s.room.id, _me, text: body.substring(0, min(body.length, AppConfig.maxChatLength)));
  }

  /// Dedication = a highlighted chat card + the song added to the queue.
  Future<void> dedicate(Track track, {required String toName, required String note}) async {
    final s = state;
    if (s == null) return;
    await _live.sendMessage(
      s.room.id,
      _me,
      text: note.trim().isEmpty ? '🎶' : note.trim(),
      kind: ChatKind.dedication,
      toName: toName.trim(),
      track: track,
    );
    // Card only if the song is already playing or queued — never a second copy.
    final queued = s.upcoming.any((q) => q.track.id == track.id);
    if (!queued && s.playback.track?.id != track.id) await playOrQueue(track);
  }

  Future<void> react(String emoji) async {
    final s = state;
    if (s == null || !Reaction.allowed.contains(emoji)) return;
    await _live.react(s.room.id, s.myUid, emoji);
  }

  // ── TransportDelegate (in-app buttons + lock screen) ─────────────────────
  @override
  Future<void> onPlay() async {
    final s = state;
    if (s == null) return;
    final p = s.playback;
    if (s.canControl && p.track != null && !p.isPlaying) {
      await _live.setTransport(s.room.id, status: PlaybackStatus.playing, positionMs: p.positionMs, by: s.myUid);
    } else if (s.locallyPaused || !_audio.playing) {
      // Listener un-mutes: rejoin the room's timeline.
      _update((cur) => cur.copyWith(locallyPaused: false));
      await _apply(state?.playback ?? p);
    }
  }

  @override
  Future<void> onPause() async {
    final s = state;
    if (s == null) return;
    await _audio.pauseLocal();
    final p = s.playback;
    if (s.canControl && p.isPlaying) {
      await _live.setTransport(
        s.room.id,
        status: PlaybackStatus.paused,
        positionMs: p.expectedPositionMs(_clock.nowMs()),
        by: s.myUid,
      );
    } else {
      _update((cur) => cur.copyWith(locallyPaused: true));
    }
  }

  @override
  Future<void> onNext() => skip();

  @override
  Future<void> onPrevious() => onSeek(Duration.zero);

  @override
  Future<void> onSeek(Duration position) async {
    final s = state;
    final track = s?.playback.track;
    if (s == null || track == null || track.isLive || !s.canControl) return;
    await _audio.seekLocal(position);
    await _live.setTransport(s.room.id, status: s.playback.status, positionMs: position.inMilliseconds, by: s.myUid);
  }
}
