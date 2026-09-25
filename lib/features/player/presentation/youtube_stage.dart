import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../core/design_system/design_system.dart';
import '../application/player_providers.dart';
import '../data/youtube_engine.dart';

/// The on-screen official YouTube player for whatever video the [PlayerHub] is
/// playing. Mounting this is what allows a video to play; unmounting it closes
/// the player, so playback can never continue off screen (YouTube API policy).
///
/// There is only ever one: screens place it through a `VideoSlot`, which
/// moves this same player (by GlobalKey) between the room, Now Playing, the
/// floating card and the PiP window. Rebuilding it would reload the video.
class YouTubeStage extends ConsumerStatefulWidget {
  const YouTubeStage({
    this.height,
    this.radius = Radii.lgAll,
    this.floating = false,
    this.fill = false,
    this.pinned = false,
    super.key,
  });

  /// Fixed height; defaults to 16:9 of the available width.
  final double? height;
  final BorderRadius radius;

  /// The app-wide floating player. Full-size stages (the default) make it
  /// step aside while they're mounted.
  final bool floating;

  /// Fill the parent exactly (the Android PiP window, which the system sizes).
  final bool fill;

  /// Keeps the video while mounted, even if other stages mount meanwhile (the
  /// PiP window, over an app that keeps rebuilding offstage).
  final bool pinned;

  /// YouTube requires an embedded player viewport of at least 200×200 px.
  static const double minSize = 200;

  @override
  ConsumerState<YouTubeStage> createState() => _YouTubeStageState();
}

class _YouTubeStageState extends ConsumerState<YouTubeStage> with WidgetsBindingObserver {
  late final YouTubeEngine _engine = ref.read(playerHubProvider).youtube;
  late final YoutubePlayerController _controller = YoutubePlayerController(
    params: const YoutubePlayerParams(
      // Our own transport drives the player so rooms stay in sync.
      showControls: false,
      showFullscreenButton: false,
      enableCaption: false,
      showVideoAnnotations: false,
      strictRelatedVideos: true,
      playsInline: true,
      videoStateUpdateInterval: 250,
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _engine.attach(_controller, pinned: widget.pinned);
    if (!widget.floating) _engine.addPrimaryStage();
  }

  /// Moved to another slot: a full-size slot counts as a primary stage (the
  /// floating card then steps aside), a floating one doesn't.
  @override
  void didUpdateWidget(YouTubeStage old) {
    super.didUpdateWidget(old);
    if (old.floating == widget.floating) return;
    widget.floating ? _engine.removePrimaryStage() : _engine.addPrimaryStage();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` (e.g. notification shade) keeps playing; background pauses.
    _engine.setForeground(state == AppLifecycleState.resumed || state == AppLifecycleState.inactive);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engine.detach(_controller);
    if (!widget.floating) _engine.removePrimaryStage();
    unawaited(_controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => YouTubeStageFrame(
    height: widget.height,
    radius: widget.radius,
    fill: widget.fill,
    builder: (width, height) => YoutubePlayer(
      controller: _controller,
      aspectRatio: width / height,
      backgroundColor: Colors.black,
      autoFullScreen: false,
      enableFullScreenOnVerticalDrag: false,
    ),
  );
}

/// The stage's box (16:9 of the width, at least 200 high, rounded). Also the
/// black placeholder a slot shows while another slot has the player, so the
/// layout doesn't jump when the player moves.
class YouTubeStageFrame extends StatelessWidget {
  const YouTubeStageFrame({this.height, this.radius = Radii.lgAll, this.fill = false, this.builder, super.key});

  final double? height;
  final BorderRadius radius;
  final bool fill;
  final Widget Function(double width, double height)? builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final h = fill ? constraints.maxHeight : math.max(height ?? width * 9 / 16, YouTubeStage.minSize);
        return ClipRRect(
          borderRadius: radius,
          child: SizedBox(
            width: width,
            height: h,
            child: ColoredBox(color: Colors.black, child: builder?.call(width, h)),
          ),
        );
      },
    );
  }
}

/// One-line reminder shown under videos, so nobody expects background play.
class VideoForegroundNote extends StatelessWidget {
  const VideoForegroundNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.smart_display_rounded, size: 14, color: context.synk.textMuted),
        const SizedBox(width: Space.xs),
        Flexible(
          child: Text(
            'Videos play while Synk is open · radio keeps playing in the background',
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(color: context.synk.textMuted),
          ),
        ),
      ],
    );
  }
}
