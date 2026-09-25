import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/application/session.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/domain/genres.dart';
import '../../catalog/domain/track.dart';
import '../../catalog/presentation/track_widgets.dart';
import '../../player/application/play_actions.dart';
import '../../rooms/application/room_providers.dart';
import '../../rooms/presentation/room_sheets.dart';
import '../../rooms/presentation/widgets/room_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final vibe = Vibes.byLabel(profile?.vibes.firstOrNull);

    Future<void> refresh() async {
      ref
        ..invalidate(liveRoomsProvider)
        ..invalidate(roomListenersPreviewProvider)
        ..invalidate(trendingVideosProvider)
        ..invalidate(nearbyStationsProvider);
      await ref.read(liveRoomsProvider.future).catchError((Object _) => const <Never>[]);
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: refresh,
        edgeOffset: MediaQuery.paddingOf(context).top,
        child: CustomScrollView(
          slivers: [
            SliverSafeArea(
              bottom: false,
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              Formatters.greeting(),
                              style: context.text.bodyLarge?.copyWith(color: context.synk.textSecondary),
                            ),
                            Text(
                              profile?.displayName ?? '',
                              style: context.text.headlineLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (profile != null)
                        Pressable(
                          onTap: () => context.go(Routes.profile),
                          semanticLabel: 'Your profile',
                          child: SynkAvatar(emoji: profile.avatarEmoji, colorIndex: profile.avatarColor, size: 44),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: _QuickActions()),
            SliverToBoxAdapter(
              child: SectionHeader('Live now', action: 'View all', onAction: () => context.push(Routes.liveRooms)),
            ),
            const SliverToBoxAdapter(child: _LiveRoomsRail()),
            const SliverToBoxAdapter(child: SectionHeader('Trending music videos')),
            const SliverToBoxAdapter(child: _TrendingVideosRail()),
            if (vibe != null) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  '${vibe.label} radio for you',
                  action: 'More',
                  onAction: () => context.push(Routes.genre(vibe.label)),
                ),
              ),
              SliverToBoxAdapter(child: _VibeRail(vibe: vibe)),
            ],
            const SliverToBoxAdapter(child: SectionHeader('Radio near you')),
            const SliverToBoxAdapter(child: _StationsRail()),
            const SliverToBoxAdapter(child: SectionHeader('Explore vibes')),
            const _VibeGrid(),
            SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + Space.xl)),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, 0),
      // IntrinsicHeight + stretch: both cards match the taller one, so a label that
      // wraps on a narrow phone (or with large text) grows the pair instead of overflowing.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.sensors_rounded,
                label: 'Go live',
                semanticLabel: 'Go live — start a room',
                filled: true,
                onTap: () => showCreateRoomSheet(context),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: _ActionCard(
                icon: Icons.pin_rounded,
                label: 'Join with code',
                semanticLabel: 'Join a room with a code',
                onTap: () => showJoinRoomSheet(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  /// Solid brand card; otherwise a raised glass card.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: Container(
        constraints: const BoxConstraints(minHeight: 96),
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: filled ? c.brand : c.surfaceRaised,
          borderRadius: Radii.lgAll,
          border: filled ? null : Border.all(color: c.glassBorder, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: filled ? c.onBrand : context.colors.primary),
            const SizedBox(height: Space.md),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleLarge?.copyWith(color: filled ? c.onBrand : c.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveRoomsRail extends ConsumerWidget {
  const _LiveRoomsRail();

  static const _height = 232 * 1.2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(liveRoomsProvider);
    // Only the horizontal carousel has a fixed height; empty/error states size to content.
    Widget carousel({required int count, required IndexedWidgetBuilder item}) => SizedBox(
      height: _height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: Space.md),
        itemBuilder: item,
      ),
    );

    return rooms.when(
      skipLoadingOnRefresh: true,
      loading: () => carousel(
        count: 3,
        item: (_, _) => const Skeleton(width: 232, height: _height, radius: Radii.xlAll),
      ),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(liveRoomsProvider)),
      data: (list) => list.isEmpty
          ? const _NoRoomsCard()
          : carousel(
              count: list.length,
              item: (_, i) => RoomCard(room: list[i]),
            ),
    );
  }
}

class _NoRoomsCard extends StatelessWidget {
  const _NoRoomsCard();

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: GlassPanel(
        color: c.surfaceRaised,
        padding: const EdgeInsets.all(Space.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: c.surfaceOverlay, shape: BoxShape.circle),
              child: Icon(Icons.nightlife_rounded, color: context.colors.primary),
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No public rooms right now', style: context.text.titleMedium),
                  const SizedBox(height: Space.xs),
                  Text('Start one — your friends will see it here.', style: context.text.bodySmall),
                  const SizedBox(height: Space.md),
                  PrimaryButton(
                    label: 'Start a room',
                    icon: Icons.sensors_rounded,
                    expand: false,
                    height: 44,
                    onPressed: () => showCreateRoomSheet(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Regional YouTube music chart (1 quota unit, cached 30 min).
class _TrendingVideosRail extends ConsumerWidget {
  const _TrendingVideosRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(youtubeEnabledProvider)) return const _VideosDisabledCard();
    final videos = ref.watch(trendingVideosProvider);
    final height = VideoCard.height(context);
    Widget rail({required int count, required IndexedWidgetBuilder item}) => SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: Space.md),
        itemBuilder: item,
      ),
    );
    return videos.when(
      loading: () => rail(
        count: 3,
        item: (_, _) => const Skeleton(width: VideoCard.width, height: VideoCard.width * 9 / 16, radius: Radii.lgAll),
      ),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(trendingVideosProvider)),
      data: (list) {
        final top = list.take(20).toList();
        return rail(
          count: top.length,
          item: (_, i) => VideoCard(track: top[i], onTap: () => playTrackFromList(context, ref, top, i)),
        );
      },
    );
  }
}

/// Shown when the build has no YouTube API key (radio still works).
class _VideosDisabledCard extends StatelessWidget {
  const _VideosDisabledCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: GlassPanel(
        color: context.synk.surfaceRaised,
        padding: const EdgeInsets.all(Space.lg),
        child: Row(
          children: [
            Icon(Icons.smart_display_rounded, color: context.colors.primary),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                'Videos are coming soon to this build. Radio works right now.',
                style: context.text.bodyMedium?.copyWith(color: context.synk.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationsRail extends ConsumerWidget {
  const _StationsRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _TrackRail(value: ref.watch(nearbyStationsProvider), onRetry: () => ref.invalidate(nearbyStationsProvider));
}

class _VibeRail extends ConsumerWidget {
  const _VibeRail({required this.vibe});

  final Vibe vibe;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _TrackRail(
    value: ref.watch(stationsByTagProvider(vibe.radioTag)),
    onRetry: () => ref.invalidate(stationsByTagProvider(vibe.radioTag)),
  );
}

/// Horizontal rail of radio-station cards.
class _TrackRail extends ConsumerWidget {
  const _TrackRail({required this.value, this.onRetry});

  final AsyncValue<List<Track>> value;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 124 + Space.sm + MediaQuery.textScalerOf(context).scale(40) + Space.xs,
      child: value.when(
        loading: () => ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          itemCount: 4,
          separatorBuilder: (_, _) => const SizedBox(width: Space.md),
          itemBuilder: (_, _) => const Skeleton(width: 124, height: 124, radius: Radii.lgAll),
        ),
        error: (e, _) => Center(
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ),
        data: (items) {
          final list = items.take(15).toList();
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (_, i) => TrackCard(track: list[i], onTap: () => playTrackFromList(context, ref, list, i)),
          );
        },
      ),
    );
  }
}

class _VibeGrid extends StatelessWidget {
  const _VibeGrid();

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: Space.md,
          crossAxisSpacing: Space.md,
          childAspectRatio: 1.9,
        ),
        itemCount: Vibes.all.length,
        itemBuilder: (_, i) {
          final v = Vibes.all[i];
          final color = SynkPalette.identityColor(v.colorIndex);
          return Pressable(
            onTap: () => context.push(Routes.genre(v.label)),
            semanticLabel: '${v.label} vibe',
            child: Container(
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(borderRadius: Radii.lgAll, color: color),
              child: Stack(
                children: [
                  Text(v.label, style: context.text.titleLarge?.copyWith(color: Colors.white)),
                  Positioned(
                    right: -6,
                    bottom: -10,
                    child: Transform.rotate(
                      angle: 0.3,
                      child: Icon(v.icon, size: 56, color: Colors.white.withValues(alpha: 0.35)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
