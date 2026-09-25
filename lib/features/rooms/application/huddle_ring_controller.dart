import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../player/data/picture_in_picture.dart';
import '../data/huddle_ringer.dart';
import '../domain/huddle_models.dart';
import '../domain/huddle_rules.dart';
import 'huddle_controller.dart';
import 'huddle_state.dart';
import 'room_providers.dart';
import 'room_session_controller.dart';

final huddleRingerProvider = Provider<HuddleRinger>((ref) => HuddleRinger());

/// A huddle ringing for the user: someone started it in the room they're in.
@immutable
class IncomingHuddle {
  const IncomingHuddle({required this.roomId, required this.roomName, required this.caller});

  final String roomId;
  final String roomName;

  /// Who started it.
  final HuddleMember caller;
}

/// The huddle ringing right now, if any.
final huddleRingProvider = NotifierProvider<HuddleRingController, IncomingHuddle?>(HuddleRingController.new);

enum _Ringing { none, inApp, notification }

/// The room the user is in; [rejoins] re-opens the huddle list.
typedef _RoomKey = ({String id, String name, int rejoins});

/// Rings everyone else in the room when someone starts a huddle, for
/// [HuddleRules.ringTime] or until they answer, decline, join it from the
/// room, or it ends:
/// * app on screen: the ringtone, under a full-screen page (see
///   `IncomingHuddleHost`). Not on that room's own screen: its huddle strip
///   already shows a Join button, so seeing it there ends the ringing;
/// * app in the background or phone locked: a call notification that rings,
///   full screen over the lock screen.
///
/// Only while the app runs. The room keeps it running in the background as
/// long as its music plays. Ringing a closed app would need push messages
/// sent from a server, which the free tier doesn't include.
class HuddleRingController extends Notifier<IncomingHuddle?> {
  /// Synchronous: an answer from the notification is taken before the app
  /// coming to the front can end the ringing (on the room's own screen).
  final StreamController<void> _accepts = StreamController.broadcast(sync: true);
  final List<StreamSubscription<Object?>> _subs = [];
  StreamSubscription<List<HuddleMember>>? _members;
  AppLifecycleListener? _lifecycle;
  Timer? _timeout;
  IncomingHuddle? _incoming;
  ({String id, String name})? _room;

  /// The room had a huddle going when we last looked, so a list that isn't
  /// empty is nothing new.
  bool _knewOne = false;
  bool _visible = true;
  String? _roomOnTop;
  _Ringing _ringing = _Ringing.none;

  HuddleRinger get _ringer => ref.read(huddleRingerProvider);

  /// The user answered, in the app or from the notification.
  /// `IncomingHuddleHost` joins the huddle and opens the room.
  Stream<void> get accepts => _accepts.stream;

  @override
  IncomingHuddle? build() {
    _visible = _onScreen(WidgetsBinding.instance.lifecycleState);
    _lifecycle = AppLifecycleListener(onStateChange: (s) => _setVisible(_onScreen(s)));
    _subs.addAll([
      _ringer.actions.listen((a) => a == RingAction.accept ? requestAccept() : decline()),
      // In the PiP window the app shows only the video: ring by notification.
      PictureInPicture.instance.modeChanges.listen(
        (_) => _setVisible(_onScreen(WidgetsBinding.instance.lifecycleState)),
      ),
    ]);
    ref.listen<_RoomKey?>(
      roomSessionProvider.select(
        (s) => s == null || s.ended ? null : (id: s.room.id, name: s.room.name, rejoins: s.rejoins),
      ),
      _watch,
      fireImmediately: true,
    );
    // Joined some other way (the room's Join button): stop ringing.
    ref.listen(huddleProvider.select((s) => s.phase != HuddlePhase.idle), (_, inHuddle) {
      if (inHuddle) _stop(release: false);
    });
    ref.onDispose(() {
      for (final s in _subs) {
        unawaited(s.cancel());
      }
      unawaited(_members?.cancel());
      _lifecycle?.dispose();
      _timeout?.cancel();
      unawaited(_ringer.ringtone(false));
      unawaited(_ringer.cancel());
      unawaited(_accepts.close());
    });
    return null;
  }

  // ── Actions ──────────────────────────────────────────────────────────────
  /// Answer (the page's Join button). Handled by `IncomingHuddleHost`.
  void requestAccept() {
    if (_incoming != null) _accepts.add(null);
  }

  void decline() => _stop();

  /// Stops ringing to answer, and returns the room whose huddle to join
  /// (null if it stopped ringing meanwhile). Call [release] once joined.
  String? take() {
    final roomId = _incoming?.roomId;
    _stop(release: false);
    return roomId;
  }

  /// Done with the lock screen. [unlock] after answering there.
  Future<void> release({required bool unlock}) => _ringer.release(unlock: unlock);

  /// The room whose screen is on top, if any (from the router).
  void setRoomOnTop(String? roomId) {
    if (roomId == _roomOnTop) return;
    _roomOnTop = roomId;
    _apply();
  }

  // ── Watching the room ────────────────────────────────────────────────────
  void _watch(_RoomKey? before, _RoomKey? now) {
    if (now?.id != before?.id) {
      _stop();
      _knewOne = false;
      // Asked on entering a room: that's when ringing becomes possible.
      if (now != null) unawaited(_ringer.requestPermission());
    }
    unawaited(_members?.cancel());
    _members = null;
    _room = now == null ? null : (id: now.id, name: now.name);
    if (now == null) return;
    // Re-opened after a dropped connection too (rejoins), like the chat: the
    // rules only serve the huddle list to people in the room.
    _members = ref
        .read(huddleSignalingProvider)
        .members(now.id)
        .listen(_onMembers, onError: (Object e, StackTrace st) => AppLogger.error('HuddleRing', e, st));
  }

  void _onMembers(List<HuddleMember> members) {
    final room = _room;
    final me = ref.read(roomSessionProvider)?.myUid;
    if (room == null || me == null) return;
    if (members.isEmpty) {
      // It ended, maybe before anyone answered.
      _knewOne = false;
      _stop();
      return;
    }
    final now = ref.read(serverClockProvider).nowMs();
    final idle = ref.read(huddleProvider).phase == HuddlePhase.idle;
    final caller = idle ? HuddleRules.caller(members, myUid: me, knewOne: _knewOne, nowMs: now) : null;
    _knewOne = true;
    if (caller == null) return;

    _incoming = IncomingHuddle(roomId: room.id, roomName: room.name, caller: caller);
    state = _incoming;
    final left = HuddleRules.ringTime.inMilliseconds - (now - caller.joinedAt);
    _timeout?.cancel();
    _timeout = Timer(Duration(milliseconds: max(left, 5000)), _stop);
    _apply();
  }

  // ── Ringing ──────────────────────────────────────────────────────────────
  static bool _onScreen(AppLifecycleState? s) =>
      (s == null || s == AppLifecycleState.resumed || s == AppLifecycleState.inactive) &&
      !PictureInPicture.instance.inPip;

  void _setVisible(bool visible) {
    if (visible == _visible) return;
    _visible = visible;
    _apply();
  }

  /// Rings the right way for where the user is.
  void _apply() {
    final incoming = _incoming;
    if (incoming != null && _visible && _roomOnTop == incoming.roomId) {
      _stop();
      return;
    }
    final want = incoming == null
        ? _Ringing.none
        : _visible
        ? _Ringing.inApp
        : _Ringing.notification;
    if (want == _ringing) return;
    _ringing = want;
    switch (want) {
      case _Ringing.none:
        unawaited(_ringer.ringtone(false));
        unawaited(_ringer.cancel());
      case _Ringing.inApp:
        unawaited(_ringer.cancel());
        unawaited(_ringer.ringtone(true));
      case _Ringing.notification:
        unawaited(_ringer.ringtone(false));
        unawaited(_ringer.notify(caller: incoming!.caller.name, room: incoming.roomName));
    }
  }

  void _stop({bool release = true}) {
    _timeout?.cancel();
    _timeout = null;
    if (_incoming == null) return;
    _incoming = null;
    state = null;
    _apply();
    if (release) unawaited(_ringer.release(unlock: false));
  }
}
