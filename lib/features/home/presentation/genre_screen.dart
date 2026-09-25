import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/domain/genres.dart';
import '../../catalog/domain/track.dart';
import '../../catalog/presentation/track_widgets.dart';
import '../../player/application/play_actions.dart';

class GenreScreen extends StatelessWidget {
  const GenreScreen({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final vibe = Vibes.byLabel(label);
    if (vibe == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: EmptyState(icon: Icons.search_off_rounded, title: 'Vibe not found'),
        ),
      );
    }
    final color = SynkPalette.identityColor(vibe.colorIndex);
    final tabs = vibe.radioFirst ? const ['Radio', 'Videos'] : const ['Videos', 'Radio'];

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (_, _) => [
            SliverAppBar(
              pinned: true,
              expandedHeight: 180,
              backgroundColor: color,
              foregroundColor: Colors.white,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(vibe.label, style: context.text.headlineSmall?.copyWith(color: Colors.white)),
                background: ColoredBox(
                  color: color,
                  child: Align(
                    alignment: const Alignment(0.9, 0.2),
                    child: Icon(vibe.icon, size: 110, color: Colors.white.withValues(alpha: 0.3)),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.sm),
                child: GlassPanel(
                  radius: Radii.pillAll,
                  padding: const EdgeInsets.all(4),
                  child: TabBar(tabs: [for (final t in tabs) Tab(height: 36, text: t)]),
                ),
              ),
            ),
          ],
          body: TabBarView(
            children: [
              for (final t in tabs)
                t == 'Videos' ? _GenreList.videos(vibe.searchQuery) : _GenreList.radio(vibe.radioTag),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenreList extends ConsumerWidget {
  const _GenreList.videos(this.key_) : radio = false;
  const _GenreList.radio(this.key_) : radio = true;

  final String key_;
  final bool radio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Track>> value = radio
        ? ref.watch(stationsByTagProvider(key_))
        : ref.watch(videoSearchProvider(key_));
    return value.when(
      loading: () => const SingleChildScrollView(child: TrackListSkeleton(count: 8)),
      error: (e, _) => ErrorState(
        error: e,
        onRetry: () => radio ? ref.invalidate(stationsByTagProvider(key_)) : ref.invalidate(videoSearchProvider(key_)),
      ),
      data: (tracks) => tracks.isEmpty
          ? const Center(
              child: EmptyState(icon: Icons.music_off_rounded, title: 'Nothing here yet'),
            )
          : ListView.builder(
              padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + Space.xxl),
              itemCount: tracks.length,
              itemBuilder: (_, i) =>
                  TrackTile(track: tracks[i], onTap: () => playTrackFromList(context, ref, tracks, i)),
            ),
    );
  }
}
