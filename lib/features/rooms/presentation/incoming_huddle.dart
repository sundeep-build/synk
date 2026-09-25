import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../application/huddle_controller.dart';
import '../application/huddle_ring_controller.dart';
import 'huddle_view.dart';

/// Mounted once above the router (see `SynkApp`), like the floating video.
/// While a huddle rings it opens [IncomingHuddleScreen] (not over that room's
/// own screen), tells the ring controller which room is on screen, and
/// carries out an answer from the page or the notification: opens the room,
/// joins its huddle and shows the call.
class IncomingHuddleHost extends ConsumerStatefulWidget {
  const IncomingHuddleHost({super.key});

  @override
  ConsumerState<IncomingHuddleHost> createState() => _IncomingHuddleHostState();
}

class _IncomingHuddleHostState extends ConsumerState<IncomingHuddleHost> {
  late final GoRouter _router = ref.read(routerProvider);
  late final StreamSubscription<void> _accepts;

  @override
  void initState() {
    super.initState();
    _accepts = ref.read(huddleRingProvider.notifier).accepts.listen((_) => unawaited(_accept()));
    _router.routerDelegate.addListener(_onRoute);
    ref.listenManual(huddleRingProvider, (_, incoming) {
      // Stopped: the page closes itself.
      if (incoming == null) return;
      final path = _path;
      if (path != Routes.incomingHuddle && path != Routes.room(incoming.roomId)) {
        unawaited(_router.push(Routes.incomingHuddle));
      }
    });
    _onRoute();
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_onRoute);
    unawaited(_accepts.cancel());
    super.dispose();
  }

  String get _path {
    final config = _router.routerDelegate.currentConfiguration;
    return config.isEmpty ? '' : config.uri.path;
  }

  /// Deferred: the router can notify mid-build, and this may stop a ring
  /// (a provider change, which isn't allowed then).
  void _onRoute() => scheduleMicrotask(() {
    if (mounted) ref.read(huddleRingProvider.notifier).setRoomOnTop(Routes.roomIn(_path));
  });

  Future<void> _accept() async {
    final ring = ref.read(huddleRingProvider.notifier);
    final roomId = ring.take();
    if (roomId == null) return;
    if (_path != Routes.room(roomId)) unawaited(_router.push(Routes.room(roomId)));
    var joined = false;
    try {
      await ref.read(huddleProvider.notifier).join();
      joined = true;
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      unawaited(ring.release(unlock: true));
    }
    // Answering a call shows the call.
    final navigator = _router.routerDelegate.navigatorKey.currentContext;
    if (joined && navigator != null && navigator.mounted) unawaited(showHuddleView(navigator));
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// "Maya started a huddle": the full-screen Join / Decline page, opened by
/// [IncomingHuddleHost] while one rings. Closes itself once the ringing
/// stops for any reason. Back declines.
class IncomingHuddleScreen extends ConsumerStatefulWidget {
  const IncomingHuddleScreen({super.key});

  @override
  ConsumerState<IncomingHuddleScreen> createState() => _IncomingHuddleScreenState();
}

class _IncomingHuddleScreenState extends ConsumerState<IncomingHuddleScreen> {
  /// Kept once the ringing stops, so the page doesn't blank while it closes.
  IncomingHuddle? _shown;

  @override
  void initState() {
    super.initState();
    _shown = ref.read(huddleRingProvider);
    // Opened just as it stopped ringing.
    if (_shown == null) WidgetsBinding.instance.addPostFrameCallback((_) => _close());
  }

  void _close() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    // Pop bypasses the PopScope below, which is for Back only. Something
    // already pushed on top (the room, when answering): take the page out.
    route.isCurrent ? navigator.pop() : navigator.removeRoute(route);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(huddleRingProvider, (_, next) {
      if (next == null) {
        _close();
      } else {
        setState(() => _shown = next);
      }
    });
    final ring = ref.read(huddleRingProvider.notifier);
    final incoming = _shown;
    final c = context.synk;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ring.decline();
      },
      child: Scaffold(
        body: AuroraBackground(
          child: SafeArea(
            child: incoming == null
                ? const SizedBox.expand()
                // Scrolls only when it can't fit (landscape, huge text).
                : LayoutBuilder(
                    builder: (context, box) => SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: box.maxHeight),
                        child: IntrinsicHeight(
                          child: Column(
                            children: [
                              const Spacer(),
                              const SizedBox(height: Space.xl),
                              Text(
                                'HUDDLE',
                                style: context.text.labelLarge?.copyWith(color: c.textSecondary, letterSpacing: 3),
                              ),
                              const SizedBox(height: Space.xl),
                              DancingAvatar(emoji: incoming.caller.emoji, colorIndex: incoming.caller.color, size: 132),
                              const SizedBox(height: Space.xl),
                              Text(
                                '${incoming.caller.name} started a huddle',
                                textAlign: TextAlign.center,
                                style: context.text.headlineSmall,
                              ),
                              const SizedBox(height: Space.sm),
                              Text(
                                incoming.roomName,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.bodyLarge?.copyWith(color: c.textSecondary),
                              ),
                              const Spacer(flex: 2),
                              const SizedBox(height: Space.xl),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _AnswerButton(
                                    icon: Icons.call_end_rounded,
                                    label: 'Decline',
                                    color: SynkPalette.danger,
                                    foreground: Colors.white,
                                    onPressed: ring.decline,
                                  ),
                                  _AnswerButton(
                                    icon: Icons.headset_mic_rounded,
                                    label: 'Join',
                                    color: SynkPalette.online,
                                    foreground: SynkPalette.ink950,
                                    onPressed: ring.requestAccept,
                                  ),
                                ],
                              ),
                              const SizedBox(height: Space.xxl),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.foreground,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color foreground;
  final VoidCallback onPressed;

  void _tap() {
    HapticFeedback.mediumImpact();
    onPressed();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    onTap: _tap,
    excludeSemantics: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _tap,
            child: SizedBox.square(dimension: 72, child: Icon(icon, size: 32, color: foreground)),
          ),
        ),
        const SizedBox(height: Space.sm),
        Text(label, style: context.text.labelLarge),
      ],
    ),
  );
}
