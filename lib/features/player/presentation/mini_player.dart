import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
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
    final c = context.synk;

    void open() => context.push(roomId != null ? Routes.room(roomId) : Routes.player);

    // A video only plays while a player is on screen. If the floating player
    // has it, the button controls it here; otherwise it opens the video.
    final isVideo = (track?.isYouTube ?? false) && !(ref.watch(videoVisibleProvider).value ?? false);

    Future<void> toggle() async {
      if (isVideo) return open();
      return roomId != null
          ? ref.read(roomSessionProvider.notifier).togglePlay()
          : ref.read(soloPlayerProvider.notifier).toggle();
    }

    return Semantics(
      container: true,
      label: roomId != null ? 'In room $roomName' : 'Now playing',
      child: InkWell(
        onTap: open,
        borderRadius: Radii.lgAll,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.sm, Space.sm, Space.xs, Space.sm),
          child: Row(
            children: [
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
                        if (roomId != null) ...[
                          EqualizerBars(active: playing, size: 10, color: c.live),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            roomId != null
                                ? 'Live in $roomName'
                                : (isVideo ? 'Tap to watch · ${track?.artist}' : track?.artist ?? ''),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall?.copyWith(color: roomId != null ? c.live : null),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (track != null)
                IconButton(
                  tooltip: isVideo ? 'Watch' : (playing ? (roomId != null && !canControl ? 'Mute' : 'Pause') : 'Play'),
                  onPressed: () => toggle().catchError((Object e) {
                    if (context.mounted) context.showError(e);
                  }),
                  icon: Icon(
                    isVideo
                        ? Icons.smart_display_rounded
                        : playing
                        ? (roomId != null && !canControl ? Icons.volume_off_rounded : Icons.pause_rounded)
                        : Icons.play_arrow_rounded,
                    size: 30,
                  ),
                ),
              if (roomId == null && track != null && !isVideo)
                IconButton(
                  tooltip: 'Next',
                  onPressed: () => ref.read(soloPlayerProvider.notifier).onNext(),
                  icon: const Icon(Icons.skip_next_rounded, size: 28),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
