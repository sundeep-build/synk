import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router/app_router.dart';
import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../auth/application/session.dart';
import '../../catalog/domain/track.dart';
import '../../rooms/application/room_session_controller.dart';
import '../application/player_providers.dart';
import 'video_slot.dart';
import 'youtube_stage.dart';

/// Keeps a YouTube video playing after the user minimises the room or the
/// Now Playing screen: a card with the official player at YouTube's minimum
/// 200×200 viewport, so the video stays on screen as the policy requires.
/// Controls sit in a bar above the video, never over it.
///
/// Drag it anywhere; let go and it springs to the nearer side, carrying the
/// fling. Drag it past an edge (or tap ⟨ ⟩) to tuck it away: the video pauses
/// (YouTube doesn't allow its sound without its picture) and the user's avatar
/// waits at that edge. Tap it to bring the video back; in a room it rejoins
/// everyone in sync.
///
/// Mounted once above the router (see `SynkApp`), so it survives navigation.
/// It stands by (a [VideoSlot] claim) while a video plays in the room, so the
/// moment the room closes it takes that same player over, mid-play.
/// Up there there's no Navigator Overlay, and `YoutubePlayer` needs one (its
/// fullscreen uses an OverlayPortal), so the card brings its own. Taps outside
/// the card fall through to the app.
class FloatingVideo extends ConsumerStatefulWidget {
  const FloatingVideo({super.key});

  @override
  ConsumerState<FloatingVideo> createState() => _FloatingVideoState();
}

class _FloatingVideoState extends ConsumerState<FloatingVideo> with SingleTickerProviderStateMixin {
  static const double _width = 220;
  static const double _barHeight = 44;
  static const double _height = _barHeight + YouTubeStage.minSize;
  static const double _margin = Space.md;
  static const double _bubble = 60;
  static const double _bubbleInset = 6;

  /// Default spot clears the dock (mini player + nav bar) on the tab screens.
  static const double _dockClearance = 150;

  /// A throw this fast toward an edge tucks the card away.
  static const double _tuckVelocity = 1500;

  /// Top-left of the card, or of the avatar bubble while tucked. Moved by a
  /// notifier (not setState), so dragging never rebuilds the player.
  final _pos = ValueNotifier<Offset?>(null);
  late final AnimationController _settle = AnimationController.unbounded(vsync: this)..addListener(_onSettle);
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;

  bool _tucked = false;
  bool _left = false;

  /// A finger is on the card: show it exactly where it is (even half off
  /// screen, on its way to being tucked).
  bool _dragging = false;
  Size _screen = Size.zero;
  EdgeInsets _safe = EdgeInsets.zero;

  /// Set from the engine's stream (an event, never mid-build), see VideoSlot.
  final _claim = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    ref
      ..listenManual(videoFloatEligibleProvider, (_, next) => _claim.value = next.value ?? false, fireImmediately: true)
      // Started playing while tucked (e.g. from the mini player): show the
      // video, never play it hidden.
      ..listenManual(isPlayingProvider, (_, playing) {
        if (playing && _tucked) _untuck(resume: false);
      });
  }

  @override
  void dispose() {
    _settle.dispose();
    _pos.dispose();
    _claim.dispose();
    super.dispose();
  }

  // ── Geometry ─────────────────────────────────────────────────────────────
  double get _minY => _safe.top + _margin;
  double _maxY(double h) => math.max(_minY, _screen.height - _safe.bottom - h - _margin);
  double get _cardMinX => _margin;
  double get _cardMaxX => math.max(_margin, _screen.width - _width - _margin);
  double get _bubbleX => _left ? _bubbleInset : _screen.width - _bubble - _bubbleInset;

  Offset get _defaultCard => Offset(_cardMaxX, _screen.height - _safe.bottom - _dockClearance - _height);

  Offset _clampCard(Offset o) => Offset(o.dx.clamp(_cardMinX, _cardMaxX), o.dy.clamp(_minY, _maxY(_height)));

  // ── Motion ───────────────────────────────────────────────────────────────
  void _onSettle() => _pos.value = Offset.lerp(_from, _to, _settle.value);

  /// Springs to [target], starting with the finger's [velocity]: a slight,
  /// lively overshoot, then it settles.
  void _springTo(Offset target, {Offset velocity = Offset.zero}) {
    final from = _pos.value ?? target;
    final distance = (target - from).distance;
    if (distance < 0.5) {
      _pos.value = target;
      return;
    }
    _from = from;
    _to = target;
    final along = (velocity.dx * (target.dx - from.dx) + velocity.dy * (target.dy - from.dy)) / (distance * distance);
    _settle.animateWith(
      SpringSimulation(const SpringDescription(mass: 1, stiffness: 420, damping: 32), 0, 1, along.clamp(-12.0, 12.0)),
    );
  }

  void _dragCard(DragUpdateDetails d) {
    _settle.stop();
    _dragging = true;
    final p = (_pos.value ?? _defaultCard) + d.delta;
    // Free to leave the screen sideways (that's how it's tucked away).
    _pos.value = Offset(p.dx.clamp(-_width * 0.75, _screen.width - _width * 0.25), p.dy.clamp(_minY, _maxY(_height)));
  }

  bool get _nearLeft => (_pos.value ?? _defaultCard).dx + _width / 2 < _screen.width / 2;

  void _releaseCard(DragEndDetails d) {
    _dragging = false;
    final p = _pos.value ?? _defaultCard;
    final v = d.velocity.pixelsPerSecond;
    final center = p.dx + _width / 2;
    if (center < _width * 0.2 || (v.dx < -_tuckVelocity && center < _screen.width / 2)) return _tuck(left: true);
    if (center > _screen.width - _width * 0.2 || (v.dx > _tuckVelocity && center > _screen.width / 2)) {
      return _tuck(left: false);
    }
    final toLeft = center + v.dx * 0.15 < _screen.width / 2;
    _springTo(Offset(toLeft ? _cardMinX : _cardMaxX, (p.dy + v.dy * 0.12).clamp(_minY, _maxY(_height))), velocity: v);
  }

  void _dragBubble(DragUpdateDetails d) {
    _settle.stop();
    _dragging = true;
    final p = (_pos.value ?? Offset(_bubbleX, _minY)) + d.delta;
    _pos.value = Offset(p.dx.clamp(0, _screen.width - _bubble), p.dy.clamp(_minY, _maxY(_bubble)));
  }

  void _releaseBubble(DragEndDetails d) {
    _dragging = false;
    final p = _pos.value ?? Offset(_bubbleX, _minY);
    final v = d.velocity.pixelsPerSecond;
    _left = p.dx + _bubble / 2 + v.dx * 0.15 < _screen.width / 2;
    _springTo(Offset(_bubbleX, (p.dy + v.dy * 0.12).clamp(_minY, _maxY(_bubble))), velocity: v);
  }

  // ── Tuck / untuck ────────────────────────────────────────────────────────
  void _tuck({required bool left}) {
    HapticFeedback.lightImpact();
    final cardY = (_pos.value ?? _defaultCard).dy;
    _left = left;
    setState(() => _tucked = true);
    final y = (cardY + _height / 2 - _bubble / 2).clamp(_minY, _maxY(_bubble));
    _pos.value = Offset(left ? -_bubble : _screen.width, y);
    _springTo(Offset(_bubbleX, y));
    unawaited(_pause().catchError(_report));
  }

  void _untuck({bool resume = true}) {
    if (!_tucked) return;
    HapticFeedback.lightImpact();
    final bubbleY = (_pos.value ?? Offset(_bubbleX, _minY)).dy;
    setState(() => _tucked = false);
    final y = (bubbleY + _bubble / 2 - _height / 2).clamp(_minY, _maxY(_height));
    _pos.value = Offset(_left ? -_width : _screen.width, y);
    _springTo(Offset(_left ? _cardMinX : _cardMaxX, y));
    if (resume) unawaited(_resume().catchError(_report));
  }

  bool get _inRoom => ref.read(roomSessionProvider) != null;

  Future<void> _pause() =>
      _inRoom ? ref.read(roomSessionProvider.notifier).muteLocally() : ref.read(soloPlayerProvider.notifier).onPause();

  /// In a room this rejoins the room's timeline (so it's back in sync).
  Future<void> _resume() =>
      _inRoom ? ref.read(roomSessionProvider.notifier).onPlay() : ref.read(soloPlayerProvider.notifier).onPlay();

  void _report(Object e) {
    if (mounted) context.showError(e);
  }

  // ── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Read here, in this widget's own build (not inside the slot's builder).
    final track = ref.watch(currentTrackProvider).value;
    final playing = ref.watch(isPlayingProvider);
    final roomId = ref.watch(roomSessionProvider.select((s) => s?.room.id));
    final me = ref.watch(currentProfileProvider.select((p) => (p?.avatarEmoji ?? '🎧', p?.avatarColor ?? 0)));
    final mq = MediaQuery.of(context);
    _screen = mq.size;
    // Keyboard up → stay above it.
    _safe = mq.padding.copyWith(bottom: math.max(mq.padding.bottom, mq.viewInsets.bottom));

    return VideoSlot(
      priority: VideoSlot.floating,
      claim: _claim,
      stage: const YouTubeStage(floating: true, height: YouTubeStage.minSize, radius: BorderRadius.zero),
      builder: (context, player) {
        if (player == null) {
          // The room (or Now Playing) has the video now: next time it floats,
          // start as the card again.
          _tucked = false;
          return const SizedBox.shrink();
        }
        final card = _card(context, player, track: track, playing: playing, roomId: roomId, me: me);
        return Overlay.wrap(
          child: ValueListenableBuilder<Offset?>(
            valueListenable: _pos,
            builder: (context, pos, _) {
              final moving = _dragging || _settle.isAnimating;
              final bubbleAt = moving && pos != null
                  ? pos
                  : Offset(_bubbleX, (pos?.dy ?? _minY).clamp(_minY, _maxY(_bubble)));
              final cardAt = _tucked ? Offset.zero : (moving && pos != null ? pos : _clampCard(pos ?? _defaultCard));
              return Stack(
                children: [
                  // Tucked: kept (paused, off stage) so it comes back without a reload.
                  Positioned(
                    left: cardAt.dx,
                    top: cardAt.dy,
                    width: _width,
                    height: _height,
                    child: Offstage(offstage: _tucked, child: card),
                  ),
                  if (_tucked)
                    Positioned(
                      left: bubbleAt.dx,
                      top: bubbleAt.dy,
                      width: _bubble,
                      height: _bubble,
                      child: _Bubble(
                        emoji: me.$1,
                        colorIndex: me.$2,
                        onTap: _untuck,
                        onPan: _dragBubble,
                        onPanEnd: _releaseBubble,
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _card(
    BuildContext context,
    Widget player, {
    required Track? track,
    required bool playing,
    required String? roomId,
    required (String, int) me,
  }) {
    final c = context.synk;

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

    Widget barButton({required IconData icon, required String label, required VoidCallback onTap}) => Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: SizedBox(
          width: 34,
          height: _barHeight,
          child: Icon(icon, size: 20, color: c.textSecondary),
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: _dragCard,
      onPanEnd: _releaseCard,
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
            SizedBox(
              height: _barHeight,
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Now playing ${track?.title ?? ''}. Open player',
                      onTap: open,
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: open,
                        child: Row(
                          children: [
                            const SizedBox(width: Space.sm),
                            // Your avatar, dancing while the music plays.
                            DancingAvatar(emoji: me.$1, colorIndex: me.$2, size: 28, dancing: playing, notes: false),
                            const SizedBox(width: Space.sm),
                            Expanded(
                              child: Text(
                                track?.title ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.labelMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Points at the nearer edge, where it tucks to.
                  ValueListenableBuilder<Offset?>(
                    valueListenable: _pos,
                    builder: (_, _, _) => barButton(
                      icon: _nearLeft ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                      label: 'Tuck the video away',
                      onTap: () => _tuck(left: _nearLeft),
                    ),
                  ),
                  barButton(icon: Icons.close_rounded, label: 'Close video', onTap: close),
                ],
              ),
            ),
            player,
          ],
        ),
      ),
    );
  }
}

/// The tucked-away card: the user's avatar at the screen edge, swaying,
/// with a play badge. Tap to bring the video back; drag along either edge.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.emoji,
    required this.colorIndex,
    required this.onTap,
    required this.onPan,
    required this.onPanEnd,
  });

  final String emoji;
  final int colorIndex;
  final VoidCallback onTap;
  final GestureDragUpdateCallback onPan;
  final GestureDragEndCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    return Semantics(
      container: true,
      button: true,
      label: 'Video tucked away. Show it again',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onPanUpdate: onPan,
        onPanEnd: onPanEnd,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.surface,
            border: Border.all(color: c.brand, width: 2.5),
            boxShadow: [BoxShadow(color: c.brand.withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.all(3),
                child: DancingAvatar(emoji: emoji, colorIndex: colorIndex, size: 49, dancing: false),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: c.brand,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.surface, width: 2),
                  ),
                  child: Icon(Icons.play_arrow_rounded, size: 14, color: c.onBrand),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
