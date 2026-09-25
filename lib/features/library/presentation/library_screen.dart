import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../catalog/domain/track.dart';
import '../../catalog/presentation/track_widgets.dart';
import '../../player/application/play_actions.dart';
import '../../player/presentation/track_actions_sheet.dart';
import '../application/library_providers.dart';
import '../domain/playlist.dart';

/// Playlists · Liked · Recent — "New playlist" is always the first tile, so
/// creating one is never hidden (a Groic review couldn't find it at all).
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 3,
      child: Scaffold(
        body: GridBackdrop(
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.lg),
                  child: SplitTitle('Your library'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: GlassPanel(
                    radius: Radii.pillAll,
                    padding: EdgeInsets.all(4),
                    child: TabBar(
                      tabs: [
                        Tab(height: 36, text: 'Playlists'),
                        Tab(height: 36, text: 'Liked'),
                        Tab(height: 36, text: 'Recent'),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: Space.sm),
                Expanded(child: TabBarView(children: [_PlaylistsTab(), _LikedTab(), _RecentTab()])),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await promptPlaylistName(context);
    if (name == null || !context.mounted) return;
    try {
      final id = await ref.read(libraryActionsProvider).createPlaylist(name);
      if (context.mounted) await context.push(Routes.playlist(id));
    } catch (e) {
      if (context.mounted) context.showError(e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final items = playlists.value ?? const <Playlist>[];
    return LayoutBuilder(
      builder: (context, box) {
        // Square cover + gap + name + song count. Height comes from the content
        // (grown with the user's text size) instead of a fixed aspect ratio,
        // which clipped the text on narrow phones.
        const columns = 2;
        final tile = (box.maxWidth - Space.gutter * 2 - Space.md * (columns - 1)) / columns;
        final extent = tile + Space.sm + MediaQuery.textScalerOf(context).scale(40);
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            Space.gutter,
            Space.md,
            Space.gutter,
            MediaQuery.paddingOf(context).bottom + 160,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: Space.lg,
            crossAxisSpacing: Space.md,
            mainAxisExtent: extent,
          ),
          itemCount: items.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Pressable(
                onTap: () => _create(context, ref),
                semanticLabel: 'New playlist',
                child: LayoutBuilder(
                  builder: (context, c) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: c.maxWidth,
                        height: c.maxWidth,
                        decoration: BoxDecoration(
                          borderRadius: Radii.xlAll,
                          border: Border.all(color: context.synk.glassBorder),
                          color: context.synk.surface,
                        ),
                        child: Center(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(color: context.synk.brand, shape: BoxShape.circle),
                            child: Icon(Icons.add_rounded, size: 30, color: context.synk.onBrand),
                          ),
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      Text('New playlist', style: context.text.titleMedium),
                    ],
                  ),
                ),
              );
            }
            final p = items[i - 1];
            return Pressable(
              onTap: () => context.push(Routes.playlist(p.id)),
              semanticLabel: '${p.name}, ${p.tracks.length} songs',
              child: LayoutBuilder(
                builder: (context, c) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Artwork(
                      url: p.coverUrl,
                      size: c.maxWidth,
                      radius: Radii.xlAll,
                      seed: p.id.hashCode,
                      icon: Icons.queue_music_rounded,
                    ),
                    const SizedBox(height: Space.sm),
                    Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                    Text('${p.tracks.length} songs', style: context.text.bodySmall),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _LikedTab extends ConsumerWidget {
  const _LikedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(likedTracksProvider);
    return liked.when(
      loading: () => const SingleChildScrollView(child: TrackListSkeleton()),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(likedTracksProvider)),
      data: (tracks) => _TrackList(
        tracks: tracks,
        empty: const EmptyState(
          icon: Icons.favorite_border_rounded,
          title: 'No likes yet',
          message: 'Tap the heart on any song or station to save it here.',
        ),
      ),
    );
  }
}

class _RecentTab extends ConsumerWidget {
  const _RecentTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _TrackList(
    tracks: ref.watch(recentTracksProvider),
    empty: const EmptyState(icon: Icons.history_rounded, title: 'Nothing played yet'),
  );
}

class _TrackList extends ConsumerWidget {
  const _TrackList({required this.tracks, required this.empty});

  final List<Track> tracks;
  final Widget empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tracks.isEmpty) return Center(child: empty);
    return TrackListView(
      tracks: tracks,
      onTap: (i) => playTrackFromList(context, ref, tracks, i),
      padding: EdgeInsets.only(top: Space.sm, bottom: MediaQuery.paddingOf(context).bottom + 160),
    );
  }
}
