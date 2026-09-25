import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/presentation/track_widgets.dart';
import '../../player/application/play_actions.dart';

/// Home → Trending videos → See all: the whole regional chart (already cached
/// by Home, so opening this costs no quota).
class TrendingScreen extends ConsumerWidget {
  const TrendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videos = ref.watch(trendingVideosProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const CircleBackButton(),
        title: SplitTitle('Trending videos', style: context.text.headlineSmall),
      ),
      body: videos.when(
        loading: () => const SingleChildScrollView(child: TrackListSkeleton(count: 10)),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(trendingVideosProvider)),
        data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.smart_display_outlined, title: 'Nothing trending right now')
            : TrackListView(
                tracks: list,
                onTap: (i) => playTrackFromList(context, ref, list, i),
                padding: EdgeInsets.only(top: Space.sm, bottom: MediaQuery.paddingOf(context).bottom + 160),
              ),
      ),
    );
  }
}
