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
        appBar: AppBar(leading: const CircleBackButton()),
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
              leading: const CircleBackButton(),
              title: SplitTitle('${vibe.label} vibe', style: context.text.headlineSmall),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
                child: Container(
                  height: 124,
                  padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: color, borderRadius: Radii.xlAll),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -Space.lg,
                        top: -Space.md,
                        child: Transform.rotate(
                          angle: 0.25,
                          child: Icon(vibe.icon, size: 150, color: Colors.white.withValues(alpha: 0.18)),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(vibe.label, style: context.text.displaySmall?.copyWith(color: Colors.white)),
                            const SizedBox(height: Space.xs),
                            Text(
                              tabs.join(' · '),
                              style: context.text.labelMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.sm),
                child: GlassPanel(
                  color: context.synk.surface,
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
          : TrackListView(
              tracks: tracks,
              onTap: (i) => playTrackFromList(context, ref, tracks, i),
              padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 160),
            ),
    );
  }
}
