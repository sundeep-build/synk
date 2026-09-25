import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../library/application/library_providers.dart';
import '../../rooms/presentation/room_sheets.dart';
import '../application/player_providers.dart';
import 'player_progress.dart';
import 'track_actions_sheet.dart';
import 'youtube_stage.dart';

/// Full-screen solo player.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider).value;
    if (track == null) {
      return Scaffold(
        appBar: AppBar(leading: const CloseButton()),
        body: const Center(
          child: EmptyState(icon: Icons.music_off_rounded, title: 'Nothing playing'),
        ),
      );
    }

    final playing = ref.watch(isPlayingProvider);
    final queue = ref.watch(soloPlayerProvider);
    final liked = ref.watch(likedIdsProvider.select((ids) => ids.contains(track.id)));
    final solo = ref.read(soloPlayerProvider.notifier);
    final size = MediaQuery.sizeOf(context);
    final art = math.min(size.width - Space.gutter * 2, size.height * 0.42);

    return Scaffold(
      body: AmbientBackdrop(
        url: track.artworkUrl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: Text(
                        track.isLive ? 'LIVE RADIO' : 'NOW PLAYING · YOUTUBE',
                        textAlign: TextAlign.center,
                        style: context.text.labelSmall?.copyWith(letterSpacing: 2, color: context.synk.textSecondary),
                      ),
                    ),
                    IconButton(
                      tooltip: 'More options',
                      icon: const Icon(Icons.more_horiz_rounded),
                      onPressed: () => showTrackActions(context, track),
                    ),
                  ],
                ),
                const Spacer(),
                if (track.isYouTube) ...[
                  // One stage for the whole screen: next/previous only swap the video.
                  const YouTubeStage(key: ValueKey('now-playing-stage')),
                  const SizedBox(height: Space.sm),
                  const VideoForegroundNote(),
                ] else
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: Radii.xlAll,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 48,
                          offset: const Offset(0, 24),
                        ),
                      ],
                    ),
                    child: AnimatedScale(
                      scale: playing ? 1 : 0.9,
                      duration: Motion.slow,
                      curve: Motion.emphasized,
                      child: Artwork(url: track.artworkUrl, size: art, radius: Radii.xlAll, seed: track.seed),
                    ),
                  ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.headlineMedium,
                          ),
                          const SizedBox(height: Space.xs),
                          Text(
                            track.artist,
                            maxLines: 1,
                            style: context.text.bodyLarge?.copyWith(color: context.synk.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: liked ? 'Unlike' : 'Like',
                      iconSize: 30,
                      color: liked ? context.synk.accent : null,
                      icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        ref.read(libraryActionsProvider).toggleLike(track).catchError((Object e) {
                          if (context.mounted) context.showError(e);
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: Space.lg),
                PlayerProgress(track: track, onSeek: solo.onSeek),
                const SizedBox(height: Space.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      tooltip: 'Previous',
                      iconSize: 36,
                      onPressed: track.isLive ? null : solo.onPrevious,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    Pressable(
                      onTap: solo.toggle,
                      semanticLabel: playing ? 'Pause' : 'Play',
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(color: context.synk.textPrimary, shape: BoxShape.circle),
                        child: Icon(
                          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 40,
                          color: context.synk.background,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next',
                      iconSize: 36,
                      onPressed: queue.hasNext ? solo.onNext : null,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: Space.xl),
                // The social hook: turn solo listening into a room in one tap.
                OutlinedButton.icon(
                  onPressed: () => showCreateRoomSheet(context, startWith: track),
                  icon: const Icon(Icons.group_add_rounded),
                  label: const Text('Listen together'),
                ),
                const SizedBox(height: Space.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
