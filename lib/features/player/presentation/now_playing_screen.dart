import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/design_system/design_system.dart';
import '../../catalog/domain/track.dart';
import '../../library/application/library_providers.dart';
import '../../rooms/presentation/room_sheets.dart';
import '../application/player_providers.dart';
import 'player_progress.dart';
import 'track_actions_sheet.dart';
import 'video_slot.dart';
import 'youtube_stage.dart';

/// Full-screen solo player: round cover (or the video), actions, waveform,
/// transport, and "Listen together" to turn it into a room.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider).value;
    if (track == null) {
      return Scaffold(
        appBar: AppBar(
          leading: const CircleBackButton(icon: Icons.keyboard_arrow_down_rounded, tooltip: 'Close'),
        ),
        body: const Center(
          child: EmptyState(icon: Icons.music_off_rounded, title: 'Nothing playing'),
        ),
      );
    }

    final playing = ref.watch(isPlayingProvider);
    final hasNext = ref.watch(soloPlayerProvider.select((q) => q.hasNext));
    final solo = ref.read(soloPlayerProvider.notifier);
    final c = context.synk;
    final size = MediaQuery.sizeOf(context);
    final art = math.min(size.width * 0.62, size.height * 0.3);

    return Scaffold(
      body: AmbientBackdrop(
        url: track.artworkUrl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Column(
              children: [
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    CircleIconButton(
                      icon: Icons.keyboard_arrow_down_rounded,
                      tooltip: 'Close',
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: Text(
                        track.isLive ? 'LIVE RADIO' : 'NOW PLAYING',
                        textAlign: TextAlign.center,
                        style: context.text.labelSmall?.copyWith(letterSpacing: 2, color: c.textSecondary),
                      ),
                    ),
                    CircleIconButton(
                      icon: Icons.share_rounded,
                      tooltip: 'Share',
                      onPressed: () => SharePlus.instance.share(ShareParams(text: _shareText(track))),
                    ),
                  ],
                ),
                const Spacer(),
                if (track.isYouTube) ...[
                  // One stage for the whole screen: next/previous only swap the video.
                  const VideoSlot(stage: YouTubeStage()),
                  const SizedBox(height: Space.sm),
                  const VideoForegroundNote(),
                ] else
                  _RoundCover(track: track, size: art, spinning: playing),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      track.isLive ? Icons.radio_rounded : Icons.smart_display_rounded,
                      size: 14,
                      color: c.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      track.isLive ? (track.genre ?? 'Live radio') : 'YouTube',
                      style: context.text.labelSmall?.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                Text(
                  track.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: context.text.headlineMedium,
                ),
                const SizedBox(height: Space.xs),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium?.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: Space.md),
                _ActionRow(track: track),
                const SizedBox(height: Space.md),
                PlayerProgress(track: track, onSeek: solo.onSeek, waveform: true),
                const SizedBox(height: Space.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      tooltip: 'Previous',
                      iconSize: 34,
                      onPressed: track.isLive ? null : solo.onPrevious,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    Pressable(
                      onTap: solo.toggle,
                      semanticLabel: playing ? 'Pause' : 'Play',
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: c.brand,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: c.brand.withValues(alpha: 0.5),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Icon(
                          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 40,
                          color: c.onBrand,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next',
                      iconSize: 34,
                      onPressed: hasNext ? solo.onNext : null,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: Space.lg),
                // The social hook: turn solo listening into a room in one tap.
                PillButton(
                  label: 'Listen together',
                  icon: Icons.group_add_rounded,
                  height: 40,
                  onPressed: () => showCreateRoomSheet(context, startWith: track),
                ),
                const SizedBox(height: Space.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _shareText(Track track) => track.isYouTube
      ? '🎧 ${track.title} — ${track.artist}\nhttps://youtu.be/${track.youtubeId}'
      : '📻 Listening to ${track.title} on Synk';
}

/// Like · Add to playlist · More, as round icons.
class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(likedIdsProvider.select((ids) => ids.contains(track.id)));
    final c = context.synk;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: liked ? 'Unlike' : 'Like',
          color: liked ? c.accent : c.textSecondary,
          icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded),
          onPressed: () {
            HapticFeedback.lightImpact();
            ref.read(libraryActionsProvider).toggleLike(track).catchError((Object e) {
              if (context.mounted) context.showError(e);
            });
          },
        ),
        const SizedBox(width: Space.lg),
        IconButton(
          tooltip: 'Add to playlist',
          color: c.textSecondary,
          icon: const Icon(Icons.playlist_add_rounded),
          onPressed: () => showTrackActions(context, track),
        ),
        const SizedBox(width: Space.lg),
        IconButton(
          tooltip: 'More options',
          color: c.textSecondary,
          icon: const Icon(Icons.more_horiz_rounded),
          onPressed: () => showTrackActions(context, track),
        ),
      ],
    );
  }
}

/// Round cover in a soft ring, turning slowly like a record while it plays.
class _RoundCover extends StatefulWidget {
  const _RoundCover({required this.track, required this.size, required this.spinning});

  final Track track;
  final double size;
  final bool spinning;

  @override
  State<_RoundCover> createState() => _RoundCoverState();
}

class _RoundCoverState extends State<_RoundCover> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 24));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_RoundCover old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final spin = widget.spinning && !MediaQuery.disableAnimationsOf(context);
    if (spin && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!spin && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: c.glassBorder),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 40, offset: const Offset(0, 18)),
        ],
      ),
      child: RepaintBoundary(
        child: RotationTransition(
          turns: _spin,
          child: Artwork(
            url: widget.track.artworkUrl,
            size: widget.size,
            radius: BorderRadius.circular(widget.size),
            seed: widget.track.seed,
            icon: widget.track.isLive ? Icons.radio_rounded : Icons.music_note_rounded,
          ),
        ),
      ),
    );
  }
}
