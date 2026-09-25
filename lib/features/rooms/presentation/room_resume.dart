import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/router/routes.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/logging/app_logger.dart';
import '../../auth/application/session.dart';
import '../application/room_providers.dart';
import '../application/room_session_controller.dart';

/// Mounted once above the router (see `SynkApp`). On launch it reopens the
/// room the user was in when the app closed (swiped away, or stopped by
/// Android), so they're back where they left off without the code. Not after
/// they left it on purpose (Leave, Exit), and not if it has ended or is
/// waiting for its host: then it's just listed on Home (Your rooms).
class RoomResumer extends ConsumerStatefulWidget {
  const RoomResumer({super.key});

  @override
  ConsumerState<RoomResumer> createState() => _RoomResumerState();
}

class _RoomResumerState extends ConsumerState<RoomResumer> {
  /// Once per sign-in: later trips to Home are the user's own doing.
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(sessionProvider, (_, session) {
      if (session is SignedOut) _tried = false;
      if (session is! SessionReady || _tried) return;
      _tried = true;
      unawaited(_resume(session.profile.uid));
    }, fireImmediately: true);
  }

  Future<void> _resume(String uid) async {
    final memory = ref.read(roomMemoryProvider);
    final roomId = memory.of(uid).active;
    if (roomId == null) return;
    try {
      final room = await ref.read(roomRepositoryProvider).get(roomId);
      if (room.closed) {
        await memory.forget(uid, roomId);
        return;
      }
      // Paused until its host is back.
      if (!room.isLive && room.hostId != uid) return;
    } on NotFoundException {
      await memory.forget(uid, roomId);
      return;
    } catch (e, st) {
      // Offline, say. It's still on Home.
      AppLogger.error('RoomResume', e, st);
      return;
    }
    if (!mounted) return;
    final router = ref.read(routerProvider);
    final path = await _settledPath(router);
    // Only from Home: an invite link opened at launch wins, and so does a
    // room the user opened meanwhile.
    if (!mounted || path != Routes.home || ref.read(roomSessionProvider) != null) return;
    unawaited(router.push(Routes.room(roomId)));
  }

  /// Where the router is once the launch redirects (splash → home) are done.
  Future<String> _settledPath(GoRouter router) async {
    String path() {
      final config = router.routerDelegate.currentConfiguration;
      return config.isEmpty ? '' : config.uri.path;
    }

    bool settled() => path().isNotEmpty && !Routes.gate.contains(path());
    if (settled()) return path();
    final done = Completer<void>();
    void check() {
      if (settled() && !done.isCompleted) done.complete();
    }

    router.routerDelegate.addListener(check);
    try {
      await done.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    } finally {
      router.routerDelegate.removeListener(check);
    }
    return path();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
