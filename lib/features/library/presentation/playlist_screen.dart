import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/utils/formatters.dart';
import '../../catalog/presentation/track_widgets.dart';
import '../../player/application/play_actions.dart';
import '../../player/presentation/track_actions_sheet.dart';
import '../../rooms/presentation/room_sheets.dart';
import '../application/library_providers.dart';
import '../domain/playlist.dart';

class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(playlistProvider(id));
    return Scaffold(
      body: playlist.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: ErrorState(error: e, onRetry: () => ref.invalidate(playlistProvider(id))),
        ),
        data: (p) => p == null
            ? const Center(
                child: EmptyState(icon: Icons.playlist_remove_rounded, title: 'Playlist not found'),
              )
            : _PlaylistBody(playlist: p),
      ),
    );
  }
}

class _PlaylistBody extends ConsumerWidget {
  const _PlaylistBody({required this.playlist});

  final Playlist playlist;

  Future<void> _menu(BuildContext context, WidgetRef ref, String action) async {
    final actions = ref.read(libraryActionsProvider);
    try {
      switch (action) {
        case 'rename':
          final name = await promptPlaylistName(context, initial: playlist.name);
          if (name != null) await actions.renamePlaylist(playlist.id, name);
        case 'delete':
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete playlist?'),
              content: Text('"${playlist.name}" will be gone for good.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: SynkPalette.danger),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (ok ?? false) {
            await actions.deletePlaylist(playlist.id);
            if (context.mounted) context.pop();
          }
      }
    } catch (e) {
      if (context.mounted) context.showError(e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = playlist.tracks;
    final cover = MediaQuery.sizeOf(context).width * 0.55;

    return AmbientBackdrop(
      url: playlist.coverUrl,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.transparent,
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Playlist options',
                onSelected: (v) => _menu(context, ref, v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Column(
                children: [
                  Artwork(
                    url: playlist.coverUrl,
                    size: cover,
                    radius: Radii.xlAll,
                    seed: playlist.id.hashCode,
                    icon: Icons.queue_music_rounded,
                  ),
                  const SizedBox(height: Space.xl),
                  Text(playlist.name, textAlign: TextAlign.center, style: context.text.headlineLarge),
                  const SizedBox(height: Space.xs),
                  Text(
                    '${tracks.length} songs · ${Formatters.duration(playlist.totalDuration)}',
                    style: context.text.bodyMedium?.copyWith(color: context.synk.textSecondary),
                  ),
                  const SizedBox(height: Space.xl),
                  Row(
                    children: [
                      Expanded(
                        child: PrimaryButton(
                          label: 'Play',
                          icon: Icons.play_arrow_rounded,
                          height: 52,
                          onPressed: tracks.isEmpty ? null : () => playTrackFromList(context, ref, tracks, 0),
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: tracks.isEmpty
                              ? null
                              : () => showCreateRoomSheet(context, startWith: tracks.first),
                          icon: const Icon(Icons.group_add_rounded),
                          label: const Text('Together'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.lg),
                ],
              ),
            ),
          ),
          if (tracks.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.playlist_add_rounded,
                title: 'Empty for now',
                message: 'Long-press any song → Add to playlist.',
              ),
            )
          else
            SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (_, i) {
                final t = tracks[i];
                return Dismissible(
                  key: ValueKey(t.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: Space.xl),
                    color: SynkPalette.danger,
                    child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                  ),
                  onDismissed: (_) =>
                      ref.read(libraryActionsProvider).removeFromPlaylist(playlist.id, t.id).catchError((Object e) {
                        if (context.mounted) context.showError(e);
                      }),
                  child: TrackTile(track: t, onTap: () => playTrackFromList(context, ref, tracks, i)),
                );
              },
            ),
          SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + Space.xxl)),
        ],
      ),
    );
  }
}
