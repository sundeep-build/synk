import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;

import '../../../core/config/app_config.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/logging/app_logger.dart';
import '../../auth/application/session.dart';
import '../../profile/domain/user_profile.dart';
import '../data/huddle_foreground_service.dart';
import '../data/huddle_media.dart';
import '../data/huddle_signaling.dart';
import '../data/peer_link.dart';
import '../domain/huddle_models.dart';
import '../domain/huddle_rules.dart';
import 'huddle_state.dart';
import 'room_session_controller.dart';

final huddleSignalingProvider = Provider<HuddleSignaling>((ref) => HuddleSignaling(ref.watch(databaseProvider)));

final huddleServiceProvider = Provider<HuddleForegroundService>((ref) => const HuddleForegroundService());

/// Who's in a room's huddle, for the banner, whether or not you've joined.
/// Listens only while a room screen shows it.
final huddleMembersProvider = StreamProvider.autoDispose.family<List<HuddleMember>, String>((ref, roomId) {
  // Re-opened after a dropped connection, like the chat: the rules only serve
  // it to people in the room.
  ref.listen(roomSessionProvider.select((s) => s?.rejoins), (before, now) {
    if (before != null && now != null && now > before) ref.invalidateSelf();
  });
  return ref.watch(huddleSignalingProvider).members(roomId);
});

/// The user's huddle. Kept alive like the room session, so the call goes on
/// while they browse other tabs or lock the phone.
final huddleProvider = NotifierProvider<HuddleController, HuddleState>(HuddleController.new);

/// Who's talking right now (uids). Sampled from WebRTC stats only while a
/// widget watches it, so a minimised huddle costs no polling.
final huddleSpeakingProvider = NotifierProvider.autoDispose<HuddleSpeaking, Set<String>>(HuddleSpeaking.new);

/// Runs a mesh call: one [PeerLink] per other member, negotiated through
/// RTDB inboxes ([HuddleSignaling]).
///
/// All connection work (member changes, incoming signals, retries, camera
/// toggles) runs one task at a time on a queue, so a connection is never
/// created twice or closed half-way through its own setup.
class HuddleController extends Notifier<HuddleState> {
  final HuddleMedia _media = HuddleMedia();
  final Map<String, PeerLink> _links = {};
  final Map<String, int> _failures = {};
  final Map<String, Timer> _retryTimers = {};
  final List<StreamSubscription<Object?>> _subs = [];
  final Set<String> _acks = {};
  final Random _random = Random.secure();
  Future<void> _tail = Future.value();
  Timer? _ackTimer;
  AppLifecycleListener? _lifecycle;
  UserProfile? _me;
  String _sid = '';
  String _roomName = '';

  /// Incremented on leave: queued work from the old session then skips.
  int _generation = 0;
  bool _cameraPausedInBackground = false;
  bool _rejoining = false;
  bool _serviceStarted = false;

  /// Read once in [build]: teardown also runs from onDispose, where the ref
  /// can no longer be used.
  late HuddleForegroundService _service;

  HuddleSignaling get _signal => ref.read(huddleSignalingProvider);

  /// Our camera preview, while it's on.
  MediaStream? get localPreview => _media.cameraStream;

  /// [uid]'s audio and video, once connected.
  MediaStream? remoteStream(String uid) => _links[uid]?.remoteStream;

  @override
  HuddleState build() {
    // Leaving the room, switching rooms, or the host ending it ends the
    // huddle too.
    ref.listen(roomSessionProvider.select((s) => s == null || s.ended ? null : s.room.id), (_, roomId) {
      if (state.roomId != null && roomId != state.roomId) unawaited(leave());
    });
    _service = ref.read(huddleServiceProvider);
    ref.onDispose(() => unawaited(_teardown()));
    return const HuddleState();
  }

  // ── Join / leave ─────────────────────────────────────────────────────────
  Future<void> join() async {
    if (state.phase != HuddlePhase.idle) return;
    final room = ref.read(roomSessionProvider);
    final me = ref.read(currentProfileProvider);
    if (room == null || room.ended || me == null) return;
    final roomId = room.room.id;
    final generation = ++_generation;
    state = HuddleState(roomId: roomId, myUid: me.uid, phase: HuddlePhase.joining);
    try {
      final current = await _signal.members(roomId).first.timeout(const Duration(seconds: 10));
      if (current.where((m) => m.uid != me.uid).length >= AppConfig.maxHuddleSize) {
        throw const ValidationException('The huddle is full right now.');
      }
      await _media.open(mic: true);
      if (generation != _generation) return _media.close();

      final sid = _newSid();
      await _signal.join(roomId, me, sid: sid, mic: true);
      if (generation != _generation) {
        // Left while the join was in flight: undo it.
        await _signal.leave(roomId, me.uid);
        return _media.close();
      }
      _me = me;
      _sid = sid;
      _roomName = room.room.name;
      _subs.addAll([
        _signal.members(roomId).listen(_onMembers, onError: (Object e, StackTrace st) => _fail('HuddleMembers', e, st)),
        _signal
            .inbox(roomId, me.uid)
            .listen(_onSignal, onError: (Object e, StackTrace st) => _fail('HuddleInbox', e, st)),
      ]);
      _lifecycle = AppLifecycleListener(onHide: _onHide, onShow: _onShow);
      _serviceStarted = true;
      unawaited(_service.start(_roomName));
      state = state.copyWith(phase: HuddlePhase.live);
      unawaited(ref.read(analyticsProvider).logEvent(name: 'huddle_join', parameters: {'size': current.length + 1}));
    } catch (e, st) {
      AppLogger.error('HuddleJoin', e, st);
      if (generation == _generation) {
        _generation++;
        state = const HuddleState();
        await _teardown();
        await _signal.leave(roomId, me.uid).catchError((Object _) {});
      }
      throw _friendly(e, camera: false);
    }
  }

  Future<void> leave() async {
    final roomId = state.roomId;
    final uid = _me?.uid ?? state.myUid;
    if (roomId == null) return;
    _generation++;
    state = const HuddleState();
    await _teardown();
    if (uid == null) return;
    try {
      await _signal.leave(roomId, uid);
    } catch (e, st) {
      AppLogger.error('HuddleLeave', e, st);
    }
  }

  Future<void> _teardown() async {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    for (final t in _retryTimers.values) {
      t.cancel();
    }
    _retryTimers.clear();
    _failures.clear();
    _ackTimer?.cancel();
    _ackTimer = null;
    _acks.clear();
    _lifecycle?.dispose();
    _lifecycle = null;
    _cameraPausedInBackground = false;
    _tail = Future.value();
    _me = null;
    _sid = '';
    final links = _links.values.toList();
    _links.clear();
    await Future.wait(links.map((l) => l.close()));
    await _media.close();
    if (_serviceStarted) {
      _serviceStarted = false;
      await _service.stop();
    }
  }

  /// A listener died (e.g. rules now deny us because we left the room).
  void _fail(String tag, Object e, StackTrace st) {
    AppLogger.error(tag, e, st);
    unawaited(leave());
  }

  // ── Controls ─────────────────────────────────────────────────────────────
  Future<void> toggleMic() async {
    final me = _me;
    final roomId = state.roomId;
    if (!state.live || me == null || roomId == null) return;
    final on = !state.mic;
    _media.setMic(on);
    state = state.copyWith(mic: on);
    // Others see the muted badge; our audio is already silent either way.
    await _signal.setMedia(roomId, me.uid, mic: on);
  }

  Future<void> toggleCamera() => setCamera(!state.cam);

  Future<void> setCamera(bool on) => _serial(() async {
    final me = _me;
    final roomId = state.roomId;
    if (!state.live || me == null || roomId == null || state.cam == on) return;
    final peers = _peerCount;
    if (on) {
      final others = state.members.where((m) => m.uid != me.uid);
      if (HuddleRules.camerasOn(others) >= AppConfig.maxHuddleCameras) {
        throw const ValidationException(
          '${AppConfig.maxHuddleCameras} cameras are already on. Try again when someone turns theirs off.',
        );
      }
      final track = await _media.openCamera().catchError((Object e) => throw _friendly(e, camera: true));
      for (final link in _links.values.toList()) {
        await link.setVideo(track, peers);
      }
      state = state.copyWith(cam: true, frontCamera: _media.frontCamera);
      // Announced once frames flow, so nobody sees an empty tile.
      await _signal.setMedia(roomId, me.uid, cam: true);
      unawaited(ref.read(analyticsProvider).logEvent(name: 'huddle_camera_on'));
    } else {
      // Announced first, so others switch to the avatar before frames stop.
      state = state.copyWith(cam: false);
      unawaited(
        _signal
            .setMedia(roomId, me.uid, cam: false)
            .catchError((Object e, StackTrace st) => AppLogger.error('HuddleCam', e, st)),
      );
      for (final link in _links.values.toList()) {
        await link.setVideo(null, peers);
      }
      await _media.closeCamera();
    }
  });

  Future<void> flipCamera() => _serial(() async {
    if (!state.cam) return;
    await _media.flipCamera();
    state = state.copyWith(frontCamera: _media.frontCamera);
  });

  Future<void> toggleSpeaker() async {
    if (!state.live) return;
    final on = !state.speaker;
    await _media.setSpeaker(on);
    state = state.copyWith(speaker: on);
  }

  /// Camera off while the app is hidden (Android blocks background camera
  /// use anyway, and it saves battery); back on when the user returns.
  void _onHide() {
    if (!state.cam) return;
    _cameraPausedInBackground = true;
    unawaited(setCamera(false).catchError((Object e, StackTrace st) => AppLogger.error('HuddleCam', e, st)));
  }

  void _onShow() {
    if (!_cameraPausedInBackground) return;
    _cameraPausedInBackground = false;
    unawaited(setCamera(true).catchError((Object e, StackTrace st) => AppLogger.error('HuddleCam', e, st)));
  }

  // ── Mesh ─────────────────────────────────────────────────────────────────
  int get _peerCount => max(0, state.members.length - 1);

  void _onMembers(List<HuddleMember> members) => _enqueue(() async {
    final me = _me;
    if (me == null) return;
    if (!members.any((m) => m.uid == me.uid)) {
      await _rejoin(me);
      return;
    }
    final others = {
      for (final m in members)
        if (m.uid != me.uid) m.uid: m,
    };
    final peersBefore = _peerCount;
    state = state.copyWith(members: members);

    // Gone, or rejoined as a new session: drop what we had with them.
    for (final uid in _links.keys.toList()) {
      final m = others[uid];
      if (m == null || m.sid != _links[uid]!.sid) await _forget(uid);
    }
    for (final uid in _failures.keys.toList()) {
      if (!others.containsKey(uid)) await _forget(uid);
    }
    // Newcomers we're meant to call.
    for (final m in others.values) {
      final waiting = _links.containsKey(m.uid) || _retryTimers.containsKey(m.uid);
      if (!waiting && HuddleRules.isOfferer(me.uid, m.uid) && !_gaveUp(m.uid)) {
        await _connect(uid: m.uid, sid: m.sid);
      }
    }
    if (state.cam && _peerCount != peersBefore) {
      for (final link in _links.values) {
        unawaited(link.applyVideoBudget(_peerCount));
      }
    }
    _publish();
  });

  /// The server dropped us (a network blip fired our disconnect cleanup).
  /// Come back as a new session; everyone reconnects to it.
  Future<void> _rejoin(UserProfile me) async {
    final roomId = state.roomId;
    if (_rejoining || roomId == null) return;
    _rejoining = true;
    try {
      for (final uid in _links.keys.toList()) {
        await _forget(uid);
      }
      _sid = _newSid();
      await _signal.join(roomId, me, sid: _sid, mic: state.mic);
      if (state.cam) await _signal.setMedia(roomId, me.uid, cam: true);
    } catch (e, st) {
      _fail('HuddleRejoin', e, st);
    } finally {
      _rejoining = false;
    }
  }

  void _onSignal(HuddleSignal s) {
    _ack(s.id);
    _enqueue(() async {
      // Addressed to an earlier join of ours: stale.
      if (s.toSid != _sid || !state.live) return;
      switch (s.type) {
        case SignalType.offer:
          // A new offer replaces whatever we had with them (their retry).
          final sdp = s.sdp;
          if (sdp == null) return;
          await _close(s.from);
          await _connect(uid: s.from, sid: s.fromSid, offerSdp: sdp);
        case SignalType.answer:
          final link = _links[s.from];
          if (link != null && link.sid == s.fromSid && s.sdp != null) await link.acceptAnswer(s.sdp!);
        case SignalType.ice:
          final link = _links[s.from];
          if (link != null && link.sid == s.fromSid) await link.addIce(s.candidates);
      }
    });
  }

  Future<void> _connect({required String uid, required String sid, String? offerSdp}) async {
    final me = _me;
    final roomId = state.roomId;
    final local = _media.stream;
    if (me == null || roomId == null || local == null) return;
    final video = state.cam ? _media.videoTrack : null;
    final mySid = _sid;
    try {
      final link = await PeerLink.open(
        uid: uid,
        sid: sid,
        offerer: offerSdp == null,
        config: _iceConfig,
        local: local,
        video: video,
        peers: _peerCount,
        send: (type, {sdp, candidates = const []}) => _signal.send(
          roomId,
          toUid: uid,
          signal: HuddleSignal(from: me.uid, fromSid: mySid, toSid: sid, type: type, sdp: sdp, candidates: candidates),
        ),
        onChange: _onLink,
      );
      _links[uid] = link;
      if (offerSdp != null) await link.acceptOffer(offerSdp, local, video, _peerCount);
    } catch (e, st) {
      AppLogger.error('HuddleConnect', e, st);
      await _close(uid);
      _retryLater(uid, sid, offerer: offerSdp == null);
    }
    _publish(bump: true);
  }

  void _onLink(PeerLink link) {
    if (!identical(_links[link.uid], link)) return;
    if (link.status == PeerStatus.connected) _failures.remove(link.uid);
    if (link.status == PeerStatus.failed) {
      _enqueue(() async {
        if (!identical(_links[link.uid], link)) return;
        await _close(link.uid);
        _retryLater(link.uid, link.sid, offerer: link.offerer);
        _publish();
      });
    }
    _publish(bump: true);
  }

  /// Rebuilds a dropped connection. The offerer side redials with backoff;
  /// the other side waits for that new offer.
  void _retryLater(String uid, String sid, {required bool offerer}) {
    final failures = _failures[uid] = (_failures[uid] ?? 0) + 1;
    if (!offerer || failures > HuddleRules.maxReconnects) return;
    _retryTimers[uid]?.cancel();
    _retryTimers[uid] = Timer(HuddleRules.reconnectDelay(failures - 1), () {
      _retryTimers.remove(uid);
      _enqueue(() async {
        final m = state.member(uid);
        if (m != null && m.sid == sid && !_links.containsKey(uid)) await _connect(uid: uid, sid: sid);
      });
    });
  }

  bool _gaveUp(String uid) => (_failures[uid] ?? 0) > HuddleRules.maxReconnects;

  Future<void> _close(String uid) async {
    final link = _links.remove(uid);
    await link?.close();
  }

  /// Closes and forgets everything about [uid] (they left or rejoined).
  Future<void> _forget(String uid) async {
    _retryTimers.remove(uid)?.cancel();
    _failures.remove(uid);
    await _close(uid);
  }

  void _publish({bool bump = false}) {
    if (!state.live) return;
    final me = _me?.uid;
    state = state.copyWith(
      bump: bump,
      peers: {
        for (final m in state.members)
          if (m.uid != me) m.uid: _links[m.uid]?.status ?? (_gaveUp(m.uid) ? PeerStatus.failed : PeerStatus.connecting),
      },
    );
  }

  /// Uids whose voice is above the talking threshold right now.
  Future<Set<String>> talking() async {
    final me = _me;
    if (!state.live || me == null) return const {};
    final links = [
      for (final l in _links.values)
        if (l.status == PeerStatus.connected && (state.member(l.uid)?.mic ?? false)) l,
    ];
    final levels = await Future.wait(links.map((l) => l.remoteLevel()));
    final out = {
      for (var i = 0; i < links.length; i++)
        if (levels[i] >= HuddleRules.speakingLevel) links[i].uid,
    };
    if (state.mic && links.isNotEmpty && await links.first.localLevel() >= HuddleRules.speakingLevel) out.add(me.uid);
    return out;
  }

  // ── Plumbing ─────────────────────────────────────────────────────────────
  /// Runs [task] after everything queued before it. Tasks queued before a
  /// leave are skipped.
  Future<T?> _serial<T>(Future<T> Function() task) {
    final generation = _generation;
    final result = _tail.then((_) => generation == _generation ? task() : Future<T?>.value());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void _enqueue(Future<void> Function() task) =>
      unawaited(_serial(task).catchError((Object e, StackTrace st) => AppLogger.error('Huddle', e, st)));

  /// Handled inbox messages are deleted in one batched write per second.
  void _ack(String id) {
    if (id.isEmpty) return;
    _acks.add(id);
    _ackTimer ??= Timer(const Duration(seconds: 1), () {
      _ackTimer = null;
      final roomId = state.roomId;
      final uid = _me?.uid;
      if (_acks.isEmpty || roomId == null || uid == null) return;
      final ids = List.of(_acks);
      _acks.clear();
      unawaited(
        _signal.ack(roomId, uid, ids).catchError((Object e, StackTrace st) => AppLogger.error('HuddleAck', e, st)),
      );
    });
  }

  String _newSid() => List.generate(12, (_) => _sidChars[_random.nextInt(_sidChars.length)]).join();

  static const _sidChars = 'abcdefghijklmnopqrstuvwxyz0123456789';

  static Map<String, dynamic> get _iceConfig => {
    'iceServers': [
      {'urls': AppConfig.stunUrls},
      if (AppConfig.turnUrls.isNotEmpty)
        {'urls': AppConfig.turnUrls, 'username': AppConfig.turnUsername, 'credential': AppConfig.turnCredential},
    ],
    'sdpSemantics': 'unified-plan',
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require',
  };

  /// flutter_webrtc reports refused permissions as plain strings.
  static AppException _friendly(Object e, {required bool camera}) {
    if (e is AppException) return e;
    if (e is FirebaseException) return AppException.from(e);
    final text = '$e';
    if (text.contains('NotAllowed') || text.contains('Permission') || text.contains('permission')) {
      return DevicePermissionException(
        camera
            ? 'Allow camera access in Settings to turn your camera on.'
            : 'Allow microphone access in Settings to join the huddle.',
        e,
      );
    }
    return AppException.from(e);
  }
}

class HuddleSpeaking extends Notifier<Set<String>> {
  static const _interval = Duration(milliseconds: 400);
  bool _sampling = false;

  @override
  Set<String> build() {
    if (!ref.watch(huddleProvider.select((s) => s.live))) return const {};
    final timer = Timer.periodic(_interval, (_) => _sample());
    ref.onDispose(timer.cancel);
    return const {};
  }

  Future<void> _sample() async {
    if (_sampling) return;
    _sampling = true;
    try {
      final now = await ref.read(huddleProvider.notifier).talking();
      if (ref.mounted && !setEquals(now, state)) state = now;
    } finally {
      _sampling = false;
    }
  }
}
