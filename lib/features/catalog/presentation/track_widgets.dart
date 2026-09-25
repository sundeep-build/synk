import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/utils/formatters.dart';
import '../../player/application/player_providers.dart';
import '../../player/presentation/track_actions_sheet.dart';
import '../domain/track.dart';

/// Song row used everywhere (search, charts, playlists, queue).
class TrackTile extends ConsumerWidget {
  const TrackTile({required this.track, required this.onTap, this.trailing, this.subtitle, this.highlight, super.key});

  final Track track;
  final VoidCallback onTap;
  final Widget? trailing;
  final String? subtitle;

  /// Forces the "current track" styling on or off. Null = follow the local
  /// player. Room lists set it, because a muted listener's player can still
  /// hold a track the room has moved past.
  final bool? highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // select(): this row rebuilds only when *its* current/playing state flips.
    final bool isCurrent = highlight ?? ref.watch(currentTrackProvider.select((t) => t.value?.id == track.id));
    final isPlaying = isCurrent && ref.watch(isPlayingProvider);
    final c = context.synk;
    final meta =
        subtitle ??
        (track.isLive
            ? track.artist
            : '${track.artist}${track.durationMs > 0 ? ' · ${Formatters.duration(track.duration)}' : ''}');

    return InkWell(
      onTap: onTap,
      onLongPress: () => showTrackActions(context, track),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.sm),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Artwork(
                  url: track.artworkUrl,
                  size: 52,
                  seed: track.seed,
                  icon: track.isLive ? Icons.radio_rounded : Icons.music_note_rounded,
                ),
                if (isCurrent)
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(color: Colors.black45, borderRadius: Radii.mdAll),
                    alignment: Alignment.center,
                    child: EqualizerBars(active: isPlaying, color: Colors.white, size: 18),
                  ),
              ],
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleMedium?.copyWith(
                      color: isCurrent ? context.colors.primary : c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                ],
              ),
            ),
            trailing ??
                IconButton(
                  tooltip: 'More options',
                  icon: Icon(Icons.more_horiz_rounded, color: c.textSecondary),
                  onPressed: () => showTrackActions(context, track),
                ),
          ],
        ),
      ),
    );
  }
}

/// Square card for horizontal rails. Works for songs and radio stations; only
/// stations get the LIVE badge.
class TrackCard extends StatelessWidget {
  const TrackCard({required this.track, required this.onTap, super.key});

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final live = track.isLive;
    return SizedBox(
      width: 124,
      child: Pressable(
        onTap: onTap,
        onLongPress: () => showTrackActions(context, track),
        semanticLabel: live ? '${track.title}, live radio' : '${track.title} by ${track.artist}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Artwork(
                  url: track.artworkUrl,
                  size: 124,
                  radius: Radii.lgAll,
                  seed: track.seed,
                  icon: live ? Icons.radio_rounded : Icons.music_note_rounded,
                ),
                if (live) const Positioned(left: 8, top: 8, child: LiveBadge(compact: true)),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
            Text(
              live ? (track.genre ?? track.artist) : track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// 16:9 card for YouTube rails: thumbnail, duration badge, title, channel.
class VideoCard extends StatelessWidget {
  const VideoCard({required this.track, required this.onTap, super.key});

  final Track track;
  final VoidCallback onTap;

  static const double width = 232;

  /// Rail height: thumbnail + two title lines + channel line, scaled with text size.
  static double height(BuildContext context) =>
      width * 9 / 16 + Space.sm + MediaQuery.textScalerOf(context).scale(58) + Space.xs;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox(
      width: width,
      child: Pressable(
        onTap: onTap,
        onLongPress: () => showTrackActions(context, track),
        semanticLabel: '${track.title} by ${track.artist}, video',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: Radii.lgAll,
              child: SizedBox(
                width: width,
                height: width * 9 / 16,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (track.artworkUrl != null)
                      CachedNetworkImage(
                        imageUrl: track.artworkUrl!,
                        memCacheWidth: (width * dpr).round(),
                        fit: BoxFit.cover,
                        fadeInDuration: Motion.fast,
                        errorWidget: (_, _, _) => ColoredBox(color: context.synk.surfaceOverlay),
                      )
                    else
                      ColoredBox(color: context.synk.surfaceOverlay),
                    if (track.durationMs > 0)
                      Positioned(
                        right: Space.sm,
                        bottom: Space.sm,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: Radii.smAll,
                          ),
                          child: Text(
                            Formatters.duration(track.duration),
                            style: context.text.labelSmall?.copyWith(color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
            Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Loading placeholder rows for track lists.
class TrackListSkeleton extends StatelessWidget {
  const TrackListSkeleton({this.count = 6, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.sm),
            child: Row(
              children: [
                Skeleton(width: 52, height: 52, radius: Radii.mdAll),
                SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton(width: 180, height: 14),
                      SizedBox(height: Space.sm),
                      Skeleton(width: 110, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
