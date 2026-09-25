import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/app_logger.dart';
import '../../features/player/application/player_providers.dart';
import '../../features/rooms/application/huddle_controller.dart';
import '../../features/rooms/application/room_session_controller.dart';

/// Wraps a root screen so Android's back button asks before closing the app,
/// instead of closing it straight away.
///
/// [onBack] runs first and can handle the press itself (e.g. the tab shell
/// returns to Home before offering to exit); it returns true if it did.
class ExitGuard extends ConsumerWidget {
  const ExitGuard({required this.child, this.onBack, super.key});

  final Widget child;
  final bool Function()? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || (onBack?.call() ?? false)) return;
        unawaited(confirmExit(context, ref));
      },
      child: child,
    );
  }
}

/// "Exit Synk?". On Exit, leaves the huddle and room (so nobody is left
/// talking to a ghost), stops playback, and closes the app.
Future<void> confirmExit(BuildContext context, WidgetRef ref) async {
  final room = ref.read(roomSessionProvider.select((s) => s?.room.name));
  final inHuddle = ref.read(huddleProvider).live;
  final playing = ref.read(isPlayingProvider);
  final message = switch ((room, inHuddle, playing)) {
    (final String name, true, _) => "You'll leave the huddle and the room “$name”.",
    (final String name, false, _) => "You'll leave the room “$name”.",
    (null, _, true) => 'Music will stop playing.',
    _ => null,
  };

  final exit = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Exit ${AppConfig.appName}?'),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Exit')),
      ],
    ),
  );
  if (!(exit ?? false)) return;

  try {
    await ref.read(huddleProvider.notifier).leave();
    await ref.read(roomSessionProvider.notifier).leave();
    await ref.read(soloPlayerProvider.notifier).stop();
  } catch (e, st) {
    AppLogger.error('Exit', e, st);
  }
  await SystemNavigator.pop();
}
