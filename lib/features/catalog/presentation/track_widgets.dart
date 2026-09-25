import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/utils/formatters.dart';
import '../../player/application/player_providers.dart';
import '../../player/presentation/track_actions_sheet.dart';
import '../domain/track.dart';

/// Song row used everywhere (search, charts, playlists, queue): cover,
/// title and artist, duration, and a round play button. The playing track's
/// row is lifted onto a panel. Long-press for actions (like, playlist, share).
class TrackTile extends ConsumerWidget {
  const TrackTile({
    required this.track,
    required this.onTap,
    this.trailing,
    this.subtitle,
    this.highlight,
    this.inset = const EdgeInsets.symmetric(horizontal: Space.gutter - Space.sm, vertical: 2),
    super.key,
  });

  final Track track;
  final VoidCallback onTap;
  final Widget? trailing;
  final String? subtitle;

  /// Forces the "current track" styling on or off. Null = follow the local
  /// player. Room lists set it, because a muted listener's player can still
  /// hold a track the room has moved past.
  final bool? highlight;

  /// Space around the row (the highlight panel sits inside it).
  final EdgeInsets inset;

  /// Stand-in for measuring the row height ([prototypeItem]) so long lists
  /// lay out in constant time.
  static const prototype = TrackTile(
    track: Track(id: '_prototype', source: TrackSource.radio, title: 'Title', artist: 'Artist', streamUrl: ''),
    onTap: _noop,
  );

  static void _noop() {}

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // select(): this row rebuilds only when *its* current/playing state flips.
    final bool isCurrent = highlight ?? ref.watch(currentTrackProvider.select((t) => t.value?.id == track.id));
    final isPlaying = isCurrent && ref.watch(isPlayingProvider);
    final c = context.synk;
    final meta = subtitle ?? track.artist;
    final duration = !track.isLive && track.durationMs > 0 ? Formatters.duration(track.duration) : null;

    return Padding(
      padding: inset,
      child: Material(
        color: isCurrent ? c.surfaceRaised : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.lgAll,
          side: isCurrent ? BorderSide(color: c.glassBorder) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: () => showTrackActions(context, track),
          child: Padding(
            padding: const EdgeInsets.all(Space.sm),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Artwork(
                      url: track.artworkUrl,
                      size: 52,
                      radius: Radii.smAll,
                      seed: track.seed,
                      icon: track.isLive ? Icons.radio_rounded : Icons.music_note_rounded,
                    ),
                    if (track.isLive && !isCurrent) const Positioned(left: 3, top: 3, child: _LiveDot()),
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
                if (trailing != null)
                  trailing!
                else ...[
                  if (isCurrent) ...[
                    EqualizerBars(active: isPlaying, size: 14, color: context.colors.tertiary),
                    const SizedBox(width: Space.sm),
                  ],
                  if (duration != null)
                    Text(
                      duration,
                      style: context.text.labelSmall?.copyWith(
                        color: c.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  const SizedBox(width: Space.md),
                  PlayStateButton(active: isCurrent, playing: isPlaying, onPressed: onTap),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      color: context.synk.live,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 1.2),
    ),
  );
}

/// Tracks in a vertical list with a fixed row height (measured once from
/// [TrackTile.prototype]): layout stays O(1) however long the list is.
class TrackListView extends StatelessWidget {
  const TrackListView({required this.tracks, required this.onTap, this.padding, this.controller, super.key});

  final List<Track> tracks;
  final void Function(int index) onTap;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => ListView.builder(
    controller: controller,
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: padding ?? EdgeInsets.only(top: Space.sm, bottom: MediaQuery.paddingOf(context).bottom + Space.xxl),
    prototypeItem: TrackTile.prototype,
    itemCount: tracks.length,
    itemBuilder: (_, i) => TrackTile(track: tracks[i], onTap: () => onTap(i)),
  );
}

/// A few rows on one rounded panel (Home's "Trending" list).
class TrackPanel extends StatelessWidget {
  const TrackPanel({required this.tracks, required this.onTap, super.key});

  final List<Track> tracks;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter - Space.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: Radii.xlAll,
          border: Border.all(color: c.glassBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Column(
            children: [
              for (var i = 0; i < tracks.length; i++)
                TrackTile(
                  track: tracks[i],
                  onTap: () => onTap(i),
                  inset: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 1),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Square card for horizontal rails (radio stations, mostly): big rounded
/// cover, name, genre, and a Play pill that turns into "Playing".
class TrackCard extends ConsumerWidget {
  const TrackCard({required this.track, required this.onTap, super.key});

  final Track track;
  final VoidCallback onTap;

  static const double width = 136;

  static const double _pill = 34;

  /// Rail height for these cards, from the theme's text styles at the
  /// user's text size (a fixed guess overflowed at the largest sizes).
  static double railHeight(BuildContext context) {
    final t = Theme.of(context).textTheme;
    double line(TextStyle? s) => (s?.fontSize ?? 14) * (s?.height ?? 1.4);
    final text = MediaQuery.textScalerOf(context).scale(line(t.titleSmall) + line(t.bodySmall));
    // +2: rounding slack between the estimate and laid-out text.
    return width + Space.sm + text + Space.sm + _pill + 2;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = track.isLive;
    final isCurrent = ref.watch(currentTrackProvider.select((t) => t.value?.id == track.id));
    final playing = isCurrent && ref.watch(isPlayingProvider);
    return SizedBox(
      width: width,
      child: Pressable(
        onTap: onTap,
        onLongPress: () => showTrackActions(context, track),
        semanticLabel: live ? '${track.title}, live radio' : '${track.title} by ${track.artist}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              children: [
                Artwork(
                  url: track.artworkUrl,
                  size: width,
                  radius: Radii.lgAll,
                  seed: track.seed,
                  icon: live ? Icons.radio_rounded : Icons.music_note_rounded,
                ),
                if (live) const Positioned(left: 8, top: 8, child: LiveBadge(compact: true)),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: context.text.titleSmall,
            ),
            Text(
              live ? (track.genre ?? track.artist) : track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: context.text.bodySmall,
            ),
            const SizedBox(height: Space.sm),
            SizedBox(
              width: double.infinity,
              child: PillButton(
                height: _pill,
                label: isCurrent ? (playing ? 'Playing' : 'Paused') : 'Play',
                icon: isCurrent ? (playing ? Icons.graphic_eq_rounded : Icons.pause_rounded) : Icons.play_arrow_rounded,
                selected: isCurrent,
                onPressed: onTap,
              ),
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
