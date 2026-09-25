import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../library/application/library_providers.dart';
import '../../../player/application/player_providers.dart';
import '../../../player/presentation/player_progress.dart';
import '../../../player/presentation/video_slot.dart';
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
    final songEnded = ref.watch(roomSessionProvider.select((s) => s?.songEnded ?? false));
    final nextQueued = ref.watch(roomSessionProvider.select((s) => s?.upcoming.isNotEmpty ?? false));
    final controller = ref.read(roomSessionProvider.notifier);

    // No song yet, or the last one ended with nothing after it: say so, and
    // offer to add one, rather than showing an empty (black) video player.
    if (track == null || songEnded) {
      return _IdlePanel(
        radio: radio,
        canControl: canControl,
        compact: compact,
        ended: track != null,
        nextQueued: nextQueued,
      );
    }

    final liked = ref.watch(likedIdsProvider.select((ids) => ids.contains(track.id)));
    final likeButton = IconButton(
      tooltip: liked ? 'Unlike' : 'Like',
      visualDensity: VisualDensity.compact,
      icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded),
      color: liked ? context.synk.accent : context.synk.textSecondary,
      onPressed: () {
        HapticFeedback.lightImpact();
        ref.read(libraryActionsProvider).toggleLike(track).catchError((Object e) {
          if (context.mounted) context.showError(e);
        });
      },
    );

    if (track.isYouTube) {
      // The slot keeps one position in the tree for both layouts, so opening
      // the keyboard shrinks the video instead of reloading it.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: Column(
          children: [
            VideoSlot(
              key: const ValueKey('room-stage'),
              stage: YouTubeStage(height: compact ? YouTubeStage.minSize : null),
            ),
            if (!compact) ...[
              const SizedBox(height: Space.xs),
              PlayerProgress(track: track, onSeek: canControl ? controller.onSeek : null, slim: true),
              Row(
                children: [
                  Expanded(
                    child: _Titles(title: track.title, artist: track.artist, small: true),
                  ),
                  likeButton,
                  const SizedBox(width: Space.xs),
                  const _PlayPauseButton(size: 46),
                  if (!track.isLive) const _SkipButton(),
                ],
              ),
            ],
          ],
        ),
      );
    }

    // Radio (and any audio): one card row, so the chat keeps the screen.
    final c = context.synk;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Container(
        padding: const EdgeInsets.all(Space.sm),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: Radii.xlAll,
          border: Border.all(color: c.glassBorder),
        ),
        child: Row(
          children: [
            Artwork(
              url: track.artworkUrl,
              size: compact ? 44 : 64,
              radius: Radii.lgAll,
              seed: track.seed,
              icon: track.isLive ? Icons.radio_rounded : Icons.music_note_rounded,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (track.isLive && !compact) ...[const LiveBadge(compact: true), const SizedBox(height: Space.xs)],
                  _Titles(title: track.title, artist: track.artist, small: true),
                ],
              ),
            ),
            if (!compact) likeButton,
            const SizedBox(width: Space.xs),
            const _PlayPauseButton(size: 46),
          ],
        ),
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
  const _IdlePanel({
    required this.radio,
    required this.canControl,
    required this.compact,
    this.ended = false,
    this.nextQueued = false,
  });

  final bool radio;
  final bool canControl;
  final bool compact;

  /// A song just finished and the room hasn't moved on yet.
  final bool ended;

  /// …and a queued song is about to start.
  final bool nextQueued;

  @override
  Widget build(BuildContext context) {
    if (compact) return const SizedBox(height: Space.sm);
    final c = context.synk;
    final canPick = !radio || canControl;
    final title = ended ? (nextQueued ? 'Next song coming up…' : 'That song ended') : 'Nothing playing yet';
    final message = ended
        ? (nextQueued ? 'Starting the next song in the queue.' : 'Nothing is up next. Add a song to keep it going.')
        : canPick
        ? (radio ? 'Pick a station to start the room.' : 'Add a song or video — everyone watches it in sync.')
        : 'The host will pick a station soon.';
    // A compact card, so the chat below keeps most of the screen.
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 0),
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: Radii.xlAll,
          border: Border.all(color: c.glassBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: c.surfaceOverlay, shape: BoxShape.circle),
              child: Icon(
                ended ? Icons.music_off_rounded : (radio ? Icons.radio_rounded : Icons.queue_music_rounded),
                color: context.colors.primary,
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleMedium),
                  const SizedBox(height: 2),
                  Text(message, style: context.text.bodySmall),
                  if (canPick && !(ended && nextQueued)) ...[
                    const SizedBox(height: Space.sm),
                    PrimaryButton(
                      label: radio ? 'Pick a station' : (ended ? 'Add a song' : 'Add the first song'),
                      icon: radio ? Icons.radio_rounded : Icons.add_rounded,
                      expand: false,
                      height: 40,
                      onPressed: () => showAddMusicSheet(context, radio: radio),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
