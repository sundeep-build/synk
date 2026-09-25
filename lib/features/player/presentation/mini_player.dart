import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../catalog/domain/track.dart';
import '../../rooms/application/room_session_controller.dart';
import '../application/player_providers.dart';

/// Compact player that lives in the floating dock above the nav bar.
/// In a room it doubles as the "you're live in X" pill.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider).value;
    final (roomId, roomName, canControl) = ref.watch(
      roomSessionProvider.select((s) => (s?.room.id, s?.room.name, s?.canControl ?? false)),
    );
    if (track == null && roomId == null) return const SizedBox.shrink();

    final playing = ref.watch(isPlayingProvider);
    final solo = ref.read(soloPlayerProvider.notifier);
    final hasNext = ref.watch(soloPlayerProvider.select((q) => q.hasNext));
    final c = context.synk;
    final inRoom = roomId != null;

    void open() => context.push(inRoom ? Routes.room(roomId) : Routes.player);

    // A video only plays while a player is on screen. If the floating player
    // has it, the button controls it here; otherwise it opens the video.
    final isVideo = (track?.isYouTube ?? false) && !(ref.watch(videoVisibleProvider).value ?? false);

    Future<void> toggle() async {
      if (isVideo) return open();
      return inRoom ? ref.read(roomSessionProvider.notifier).togglePlay() : solo.toggle();
    }

    void report(Object e) {
      if (context.mounted) context.showError(e);
    }

    final muteOnly = inRoom && !canControl;
    return Semantics(
      container: true,
      label: inRoom ? 'In room $roomName' : 'Now playing',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: open,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xl)),
            child: Padding(
              padding: EdgeInsets.fromLTRB(inRoom ? Space.md : Space.xs, Space.sm, Space.sm, Space.sm),
              child: Row(
                children: [
                  if (!inRoom)
                    IconButton(
                      tooltip: 'Stop',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close_rounded, size: 20, color: c.textSecondary),
                      onPressed: () => solo.stop().catchError(report),
                    ),
                  Artwork(url: track?.artworkUrl, size: 44, radius: Radii.smAll, seed: track?.seed ?? 0),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track?.title ?? 'Waiting for the first song…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (inRoom) ...[
                              EqualizerBars(active: playing, size: 10, color: c.live),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                inRoom
                                    ? 'Live in $roomName'
                                    : (isVideo ? 'Tap to watch · ${track?.artist}' : track?.artist ?? ''),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.bodySmall?.copyWith(color: inRoom ? c.live : null),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!inRoom && track != null && !isVideo)
                    IconButton(
                      tooltip: 'Previous',
                      visualDensity: VisualDensity.compact,
                      onPressed: track.isLive ? null : () => solo.onPrevious().catchError(report),
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                  if (track != null)
                    CircleIconButton(
                      size: 40,
                      tooltip: isVideo ? 'Watch' : (playing ? (muteOnly ? 'Mute' : 'Pause') : 'Play'),
                      onPressed: () => toggle().catchError(report),
                      icon: isVideo
                          ? Icons.smart_display_rounded
                          : playing
                          ? (muteOnly ? Icons.volume_off_rounded : Icons.pause_rounded)
                          : Icons.play_arrow_rounded,
                    ),
                  if (!inRoom && track != null && !isVideo)
                    IconButton(
                      tooltip: 'Next',
                      visualDensity: VisualDensity.compact,
                      onPressed: hasNext ? () => solo.onNext().catchError(report) : null,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                ],
              ),
            ),
          ),
          if (track != null && !track.isLive) _MiniProgress(track: track),
        ],
      ),
    );
  }
}

/// Hairline progress under the mini player. Its own widget, so only this
/// line rebuilds at position-tick rate.
class _MiniProgress extends ConsumerWidget {
  const _MiniProgress({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = track.durationMs;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final fraction = total <= 0 ? 0.0 : (position.inMilliseconds / total).clamp(0.0, 1.0);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        child: SizedBox(
          height: 2,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction,
              child: ColoredBox(color: context.colors.tertiary),
            ),
          ),
        ),
      ),
    );
  }
}
