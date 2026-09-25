import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router/app_router.dart';
import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../rooms/application/room_session_controller.dart';
import '../application/player_providers.dart';
import 'youtube_stage.dart';

/// Keeps a YouTube video playing after the user minimises the room or the
/// Now Playing screen: a draggable card with the official player at YouTube's
/// minimum 200×200 viewport, so the video stays on screen as the policy
/// requires. Controls sit in a bar above the video, never over it.
///
/// Mounted once above the router (see `SynkApp`), so it survives navigation.
/// Up there there's no Navigator Overlay, and `YoutubePlayer` needs one (its
/// fullscreen uses an OverlayPortal), so the card brings its own. Taps outside
/// the card fall through to the app.
class FloatingVideo extends ConsumerStatefulWidget {
  const FloatingVideo({super.key});

  @override
  ConsumerState<FloatingVideo> createState() => _FloatingVideoState();
}

class _FloatingVideoState extends ConsumerState<FloatingVideo> {
  static const double _width = 220;
  static const double _barHeight = 40;
  static const double _height = _barHeight + YouTubeStage.minSize;
  static const double _margin = Space.md;

  /// Default spot clears the dock (mini player + nav bar) on the tab screens.
  static const double _dockClearance = 150;

  /// Top-left corner; null until the user drags it.
  Offset? _offset;
  bool _dragging = false;

  Offset _clamp(Offset o, Size screen, EdgeInsets safe) {
    final minY = safe.top + _margin;
    final maxX = math.max(_margin, screen.width - _width - _margin);
    final maxY = math.max(minY, screen.height - safe.bottom - _height - _margin);
    return Offset(o.dx.clamp(_margin, maxX), o.dy.clamp(minY, maxY));
  }

  @override
  Widget build(BuildContext context) {
    final show = ref.watch(floatingVideoProvider).value ?? false;
    if (!show) return const SizedBox.shrink();

    final track = ref.watch(currentTrackProvider).value;
    final playing = ref.watch(isPlayingProvider);
    final roomId = ref.watch(roomSessionProvider.select((s) => s?.room.id));
    final c = context.synk;

    final mq = MediaQuery.of(context);
    final screen = mq.size;
    // Keyboard up → stay above it.
    final safe = mq.padding.copyWith(bottom: math.max(mq.padding.bottom, mq.viewInsets.bottom));
    final fallback = Offset(screen.width - _width - _margin, screen.height - safe.bottom - _dockClearance - _height);
    final pos = _clamp(_offset ?? fallback, screen, safe);

    void open() => ref.read(routerProvider).push(roomId != null ? Routes.room(roomId) : Routes.player);

    void close() {
      final pause = roomId != null
          ? ref.read(roomSessionProvider.notifier).muteLocally()
          : ref.read(soloPlayerProvider.notifier).onPause();
      // A pause alone keeps the card up; ✕ also puts it away.
      ref.read(playerHubProvider).youtube.dismissFloating();
      pause.catchError((Object e) {
        if (context.mounted) context.showError(e);
      });
    }

    final card = AnimatedPositioned(
      duration: _dragging ? Duration.zero : Motion.medium,
      curve: Motion.emphasized,
      left: pos.dx,
      top: pos.dy,
      width: _width,
      height: _height,
      child: Material(
        color: c.surfaceRaised,
        elevation: 12,
        shadowColor: Colors.black,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.lgAll,
          side: BorderSide(color: c.glassBorder),
        ),
        child: Column(
          children: [
            Semantics(
              button: true,
              label: 'Now playing ${track?.title ?? ''}. Open player',
              onTap: open,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: open,
                onPanStart: (_) => setState(() => _dragging = true),
                onPanUpdate: (d) => setState(() => _offset = _clamp(pos + d.delta, screen, safe)),
                onPanEnd: (_) => setState(() {
                  _dragging = false;
                  // Snap to the nearer side so it never sits mid-screen.
                  final left = pos.dx + _width / 2 < screen.width / 2;
                  _offset = Offset(left ? _margin : screen.width - _width - _margin, pos.dy);
                }),
                child: SizedBox(
                  height: _barHeight,
                  child: Row(
                    children: [
                      const SizedBox(width: Space.md),
                      EqualizerBars(active: playing, size: 12, color: context.colors.primary),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          track?.title ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelMedium,
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: 'Close video',
                        onTap: close,
                        excludeSemantics: true,
                        child: InkResponse(
                          onTap: close,
                          radius: 20,
                          child: SizedBox.square(
                            dimension: _barHeight,
                            child: Icon(Icons.close_rounded, size: 20, color: c.textSecondary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const YouTubeStage(
              key: ValueKey('floating-stage'),
              floating: true,
              height: YouTubeStage.minSize,
              radius: BorderRadius.zero,
            ),
          ],
        ),
      ),
    );
    return Overlay.wrap(child: Stack(children: [card]));
  }
}
