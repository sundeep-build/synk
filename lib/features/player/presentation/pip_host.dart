import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../rooms/application/room_session_controller.dart';
import '../application/player_providers.dart';
import '../data/picture_in_picture.dart';
import 'youtube_stage.dart';

/// A video is meant to be playing, so leaving the app should go to
/// picture-in-picture. Based on intent, not the player's reported state, so a
/// handover between stages or buffering doesn't disarm it.
final pipEligibleProvider = Provider<bool>(
  (ref) =>
      (ref.watch(currentTrackProvider).value?.isYouTube ?? false) && (ref.watch(videoWantsPlayProvider).value ?? false),
);

/// Wraps the whole app. Arms PiP while a video plays, and in PiP shows only
/// the video, full-bleed. The app stays mounted (offstage, tickers paused)
/// underneath, so coming back restores every screen exactly as it was and the
/// video hands back to the stage the user left.
class PipHost extends ConsumerStatefulWidget {
  const PipHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PipHost> createState() => _PipHostState();
}

class _PipHostState extends ConsumerState<PipHost> {
  final _pip = PictureInPicture.instance;
  late final List<StreamSubscription<Object?>> _subs;
  late bool _inPip = _pip.inPip;

  @override
  void initState() {
    super.initState();
    _subs = [
      _pip.modeChanges.listen((v) => setState(() => _inPip = v)),
      // Closing the window means "stop", not "resume next time I open the app".
      _pip.dismissals.listen((_) => _stopVideo()),
    ];
    ref.listenManual(pipEligibleProvider, (_, armed) => _pip.setAutoEnter(armed), fireImmediately: true);
  }

  void _stopVideo() {
    final inRoom = ref.read(roomSessionProvider) != null;
    unawaited(
      inRoom ? ref.read(roomSessionProvider.notifier).muteLocally() : ref.read(soloPlayerProvider.notifier).onPause(),
    );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = _inPip ? ref.watch(currentTrackProvider).value : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Same slot either way, so entering PiP never remounts the app.
        Offstage(
          offstage: _inPip,
          child: TickerMode(enabled: !_inPip, child: widget.child),
        ),
        if (_inPip)
          // Own Overlay: this sits above the Navigator, and YoutubePlayer needs one.
          Overlay.wrap(
            child: ColoredBox(
              color: Colors.black,
              child: (track?.isYouTube ?? false)
                  // Pinned: stages the offstage app mounts meanwhile can't take the video.
                  ? const YouTubeStage(
                      key: ValueKey('pip-stage'),
                      floating: true,
                      fill: true,
                      pinned: true,
                      radius: BorderRadius.zero,
                    )
                  // The video ended or switched to radio while in PiP: say
                  // what's on instead of showing a dead player.
                  : _PipNowPlaying(title: track?.title, artworkUrl: track?.artworkUrl, seed: track?.seed ?? 0),
            ),
          ),
      ],
    );
  }
}

class _PipNowPlaying extends StatelessWidget {
  const _PipNowPlaying({required this.title, required this.artworkUrl, required this.seed});

  final String? title;
  final String? artworkUrl;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final art = (box.maxHeight * 0.6).clamp(24.0, 96.0);
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Artwork(url: artworkUrl, size: art, radius: Radii.smAll, seed: seed),
                if (title != null) ...[
                  const SizedBox(width: Space.sm),
                  Flexible(
                    child: Text(
                      title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelMedium?.copyWith(color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
