import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/router/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/utils/validators.dart';
import '../../catalog/domain/track.dart';
import '../../library/application/library_providers.dart';
import '../../rooms/application/room_session_controller.dart';
import '../../rooms/domain/room.dart';
import '../../rooms/presentation/dedicate_sheet.dart';
import '../application/player_providers.dart';

Future<void> showTrackActions(BuildContext context, Track track) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (_) => _TrackActionsSheet(track: track),
);

class _TrackActionsSheet extends ConsumerWidget {
  const _TrackActionsSheet({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (inRoom, canControl, queued, isRoomTrack, playsNow) = ref.watch(
      roomSessionProvider.select(
        (s) => (
          s != null && !s.ended,
          s?.canControl ?? false,
          s?.upcoming.where((q) => q.track.id == track.id).firstOrNull,
          s?.playback.track?.id == track.id,
          // Mirrors playOrQueue: a controller in a radio or idle room plays it at once.
          s != null && s.canControl && (s.room.mode == RoomMode.radio || s.playback.track == null),
        ),
      ),
    );
    final liked = ref.watch(likedIdsProvider.select((ids) => ids.contains(track.id)));

    Future<void> run(Future<void> Function() action, {String? done}) async {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      try {
        await action();
        if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
      } catch (e) {
        messenger.showAppError(e);
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.md),
              child: Row(
                children: [
                  Artwork(url: track.artworkUrl, size: 56, seed: track.seed),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          style: context.text.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(track.artist, style: context.text.bodySmall, maxLines: 1),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            if (inRoom) ...[
              if (queued != null && canControl)
                ListTile(
                  leading: const Icon(Icons.play_arrow_rounded),
                  title: const Text('Play now'),
                  onTap: () => run(() => ref.read(roomSessionProvider.notifier).playNow(queued)),
                )
              else if (queued != null)
                const ListTile(enabled: false, leading: Icon(Icons.check_rounded), title: Text('Already in the queue'))
              else if (!isRoomTrack)
                ListTile(
                  leading: Icon(playsNow ? Icons.play_arrow_rounded : Icons.queue_music_rounded),
                  title: Text(playsNow ? 'Play now' : 'Add to room queue'),
                  onTap: () => run(
                    () => ref.read(roomSessionProvider.notifier).playOrQueue(track),
                    done: playsNow ? null : 'Added to the room',
                  ),
                ),
              if (!track.isLive)
                ListTile(
                  leading: const Icon(Icons.card_giftcard_rounded),
                  title: const Text('Dedicate to someone'),
                  onTap: () {
                    Navigator.of(context).pop();
                    showDedicateSheet(context, track);
                  },
                ),
            ] else
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: const Text('Play now'),
                onTap: () {
                  final router = GoRouter.of(context);
                  run(() async {
                    await ref.read(soloPlayerProvider.notifier).playOne(track);
                    // Videos only play while their player is on screen.
                    if (track.isYouTube) await router.push(Routes.player);
                  });
                },
              ),
            ListTile(
              leading: Icon(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: liked ? context.synk.accent : null,
              ),
              title: Text(liked ? 'Remove from Liked' : 'Like'),
              onTap: () => run(() => ref.read(libraryActionsProvider).toggleLike(track)),
            ),
            if (!track.isLive)
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded),
                title: const Text('Add to playlist'),
                onTap: () {
                  Navigator.of(context).pop();
                  showAddToPlaylistSheet(context, track);
                },
              ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('Share'),
              onTap: () => run(
                () => SharePlus.instance.share(
                  ShareParams(text: '🎧 ${track.title} — ${track.artist}\nListening on ${AppConfig.appName}'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showAddToPlaylistSheet(BuildContext context, Track track) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  builder: (_) => _AddToPlaylistSheet(track: track),
);

class _AddToPlaylistSheet extends ConsumerWidget {
  const _AddToPlaylistSheet({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider).value ?? const [];
    final actions = ref.read(libraryActionsProvider);

    Future<void> add(String id, String name) async {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      try {
        final added = await actions.addToPlaylist(id, track);
        messenger.showSnackBar(SnackBar(content: Text(added ? 'Added to $name' : 'Already in $name')));
      } catch (e) {
        messenger.showAppError(e);
      }
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
              child: Text('Add to playlist', style: context.text.titleLarge),
            ),
            ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: context.synk.brand, borderRadius: Radii.mdAll),
                child: Icon(Icons.add_rounded, color: context.synk.onBrand),
              ),
              title: const Text('New playlist'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final name = await promptPlaylistName(context);
                if (name == null) return;
                try {
                  await actions.createPlaylist(name, firstTrack: track);
                  if (context.mounted) Navigator.of(context).pop();
                  messenger.showSnackBar(SnackBar(content: Text('Created $name')));
                } catch (e) {
                  messenger.showAppError(e);
                }
              },
            ),
            for (final p in playlists)
              ListTile(
                leading: Artwork(url: p.coverUrl, size: 48, seed: p.id.hashCode, icon: Icons.queue_music_rounded),
                title: Text(p.name),
                subtitle: Text('${p.tracks.length} songs'),
                onTap: () => add(p.id, p.name),
              ),
          ],
        ),
      ),
    );
  }
}

Future<String?> promptPlaylistName(BuildContext context, {String initial = ''}) => showDialog<String>(
  context: context,
  useRootNavigator: true,
  builder: (_) => _PlaylistNameDialog(initial: initial),
);

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({required this.initial});

  final String initial;

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial.isEmpty ? 'New playlist' : 'Rename playlist'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Late night drives'),
          validator: (v) => Validators.playlistName(v ?? ''),
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
