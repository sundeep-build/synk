import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../library/application/library_providers.dart';
import '../../../player/application/player_providers.dart';
import '../../../player/presentation/player_progress.dart';
import '../../../player/presentation/youtube_stage.dart';
import '../../application/room_session_controller.dart';
import '../../domain/room.dart';
import '../add_music_sheet.dart';

/// Artwork + synced progress + transport. Collapses to a single row while the
/// keyboard is open so chat stays usable on small phones.
class RoomNowPlaying extends ConsumerWidget {
  const RoomNowPlaying({required this.compact, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(roomSessionProvider.select((s) => s?.playback));
    final canControl = ref.watch(roomSessionProvider.select((s) => s?.canControl ?? false));
    final radio = ref.watch(roomSessionProvider.select((s) => s?.room.mode == RoomMode.radio));
    final track = playback?.track;
    final controller = ref.read(roomSessionProvider.notifier);

    if (track == null) {
      return _IdlePanel(radio: radio, canControl: canControl, compact: compact);
    }

    final liked = ref.watch(likedIdsProvider.select((ids) => ids.contains(track.id)));
    final likeButton = IconButton(
      tooltip: liked ? 'Unlike' : 'Like',
      icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded),
      color: liked ? context.synk.accent : context.synk.textSecondary,
      onPressed: () {
        HapticFeedback.lightImpact();
        ref.read(libraryActionsProvider).toggleLike(track).catchError((Object e) {
          if (context.mounted) context.showError(e);
        });
      },
    );

    final controls = Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: radio ? 'Change station' : 'Add a song',
          icon: Icon(radio ? Icons.radio_rounded : Icons.playlist_add_rounded),
          onPressed: radio && !canControl ? null : () => showAddMusicSheet(context, radio: radio),
        ),
        const _PlayPauseButton(size: 64),
        if (!track.isLive) const _SkipButton() else const SizedBox(width: 48),
      ],
    );

    if (track.isYouTube) {
      // The stage keeps one position in the tree for both layouts, so opening
      // the keyboard shrinks it instead of reloading the player.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: Column(
          children: [
            YouTubeStage(key: const ValueKey('room-stage'), height: compact ? YouTubeStage.minSize : null),
            if (!compact) ...[
              const SizedBox(height: Space.md),
              Row(
                children: [
                  Expanded(
                    child: _Titles(title: track.title, artist: track.artist),
                  ),
                  likeButton,
                ],
              ),
              const SizedBox(height: Space.xs),
              PlayerProgress(track: track, onSeek: canControl ? controller.onSeek : null),
              controls,
            ],
          ],
        ),
      );
    }

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.sm),
        child: Row(
          children: [
            Artwork(url: track.artworkUrl, size: 48, seed: track.seed),
            const SizedBox(width: Space.md),
            Expanded(
              child: _Titles(title: track.title, artist: track.artist, small: true),
            ),
            const _PlayPauseButton(size: 44),
          ],
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height;
    // Shrink artwork on short screens so chat keeps at least ~40% height.
    final art = math.min(width * 0.56, height * 0.26).clamp(120.0, 280.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: Radii.xlAll,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 40, offset: const Offset(0, 16)),
              ],
            ),
            child: Hero(
              tag: 'room-art',
              child: Artwork(url: track.artworkUrl, size: art, radius: Radii.xlAll, seed: track.seed),
            ),
          ),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              Expanded(
                child: _Titles(title: track.title, artist: track.artist),
              ),
              likeButton,
            ],
          ),
          const SizedBox(height: Space.sm),
          PlayerProgress(track: track, onSeek: canControl ? controller.onSeek : null),
          const SizedBox(height: Space.xs),
          controls,
        ],
      ),
    );
  }
}

class _Titles extends StatelessWidget {
  const _Titles({required this.title, required this.artist, this.small = false});

  final String title;
  final String artist;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: small ? context.text.titleMedium : context.text.headlineSmall,
        ),
        const SizedBox(height: 2),
        Text(
          artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.bodyMedium?.copyWith(color: context.synk.textSecondary),
        ),
      ],
    );
  }
}

class _PlayPauseButton extends ConsumerWidget {
  const _PlayPauseButton({required this.size});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(isPlayingProvider);
    final canControl = ref.watch(roomSessionProvider.select((s) => s?.canControl ?? false));
    // Listeners' pause mutes only their device; label it honestly.
    final label = playing ? (canControl ? 'Pause for everyone' : 'Mute on this device') : 'Play';
    return Tooltip(
      message: label,
      child: Pressable(
        onTap: () => ref.read(roomSessionProvider.notifier).togglePlay().catchError((Object e) {
          if (context.mounted) context.showError(e);
        }),
        semanticLabel: label,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: context.synk.textPrimary, shape: BoxShape.circle),
          child: Icon(
            playing ? (canControl ? Icons.pause_rounded : Icons.volume_off_rounded) : Icons.play_arrow_rounded,
            size: size * 0.5,
            color: context.synk.background,
          ),
        ),
      ),
    );
  }
}

class _SkipButton extends ConsumerWidget {
  const _SkipButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (canControl, votes, needed, voted) = ref.watch(
      roomSessionProvider.select(
        (s) => (s?.canControl ?? false, s?.skipVotesForCurrent ?? 0, s?.skipThreshold ?? 1, s?.iVotedSkip ?? false),
      ),
    );
    Future<void> skip() => ref.read(roomSessionProvider.notifier).skip().catchError((Object e) {
      if (context.mounted) context.showError(e);
    });

    if (canControl) {
      return IconButton(tooltip: 'Skip', icon: const Icon(Icons.skip_next_rounded, size: 32), onPressed: skip);
    }
    return TextButton.icon(
      onPressed: voted ? null : skip,
      icon: const Icon(Icons.how_to_vote_rounded, size: 20),
      label: Text('Skip $votes/$needed'),
    );
  }
}

class _IdlePanel extends StatelessWidget {
  const _IdlePanel({required this.radio, required this.canControl, required this.compact});

  final bool radio;
  final bool canControl;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) return const SizedBox(height: Space.sm);
    final canPick = !radio || canControl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.sm),
      child: GlassPanel(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          children: [
            Icon(radio ? Icons.radio_rounded : Icons.queue_music_rounded, size: 40, color: context.colors.primary),
            const SizedBox(height: Space.md),
            Text('Nothing playing yet', style: context.text.titleLarge),
            const SizedBox(height: Space.xs),
            Text(
              canPick
                  ? (radio ? 'Pick a station to start the room.' : 'Add a song or video — everyone watches it in sync.')
                  : 'The host will pick a station soon.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(color: context.synk.textSecondary),
            ),
            if (canPick) ...[
              const SizedBox(height: Space.lg),
              PrimaryButton(
                label: radio ? 'Pick a station' : 'Add the first song',
                icon: radio ? Icons.radio_rounded : Icons.add_rounded,
                expand: false,
                height: 48,
                onPressed: () => showAddMusicSheet(context, radio: radio),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
