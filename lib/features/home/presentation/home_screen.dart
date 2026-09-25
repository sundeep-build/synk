import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/router/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/application/session.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/domain/genres.dart';
import '../../catalog/domain/track.dart';
import '../../catalog/presentation/track_widgets.dart';
import '../../player/application/play_actions.dart';
import '../../rooms/application/room_providers.dart';
import '../../rooms/application/room_session_controller.dart';
import '../../rooms/domain/room.dart';
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
        ..invalidate(myRoomsProvider)
        ..invalidate(roomListenersPreviewProvider)
        ..invalidate(trendingVideosProvider)
        ..invalidate(nearbyStationsProvider);
      await ref.read(liveRoomsProvider.future).catchError((Object _) => const <Room>[]);
    }

    return Scaffold(
      body: GridBackdrop(
        child: RefreshIndicator(
          onRefresh: refresh,
          edgeOffset: MediaQuery.paddingOf(context).top,
          child: CustomScrollView(
            slivers: [
              SliverSafeArea(
                bottom: false,
                sliver: SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const BrandWordmark(),
                            const Spacer(),
                            CircleIconButton(
                              icon: Icons.manage_search_rounded,
                              tooltip: 'Search',
                              onPressed: () => context.go(Routes.search),
                            ),
                            const SizedBox(width: Space.sm),
                            if (profile != null)
                              Pressable(
                                onTap: () => context.go(Routes.profile),
                                semanticLabel: 'Your profile',
                                child: SynkAvatar(
                                  emoji: profile.avatarEmoji,
                                  colorIndex: profile.avatarColor,
                                  size: 40,
                                  ring: true,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: Space.xl),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${Formatters.greeting()},\n',
                                style: context
                                    .weight(context.text.headlineLarge, FontWeight.w400)
                                    .copyWith(color: context.synk.textSecondary),
                              ),
                              TextSpan(text: profile?.displayName ?? ''),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.headlineLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: _QuickActions()),
              const SliverToBoxAdapter(child: _MyRooms()),
              SliverToBoxAdapter(
                child: SectionHeader(
                  'Live now',
                  action: 'See all',
                  accent: context.synk.live,
                  onAction: () => context.push(Routes.liveRooms),
                ),
              ),
              const SliverToBoxAdapter(child: _LiveRoomsCarousel()),
              const SliverToBoxAdapter(child: _TrendingVideos()),
              if (vibe != null) ...[
                SliverToBoxAdapter(
                  child: SectionHeader(
                    '${vibe.label} radio for you',
                    action: 'More',
                    accent: context.synk.accent,
                    onAction: () => context.push(Routes.genre(vibe.label)),
                  ),
                ),
                SliverToBoxAdapter(child: _VibeRail(vibe: vibe)),
              ],
              const SliverToBoxAdapter(child: SectionHeader('Radio near you')),
              const SliverToBoxAdapter(child: _StationsRail()),
              SliverToBoxAdapter(child: SectionHeader('Explore vibes', accent: context.synk.brand)),
              const _VibeGrid(),
              // Clears the floating dock.
              SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 160)),
            ],
          ),
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
                caption: 'Start a room',
                filled: true,
                onTap: () => showCreateRoomSheet(context),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: _ActionCard(
                icon: Icons.pin_rounded,
                label: 'Join',
                caption: 'With a room code',
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
    required this.caption,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onTap;

  /// Solid brand card; otherwise a raised panel.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    final fg = filled ? c.onBrand : c.textPrimary;
    return Pressable(
      onTap: onTap,
      semanticLabel: '$label — $caption',
      child: Container(
        constraints: const BoxConstraints(minHeight: 104),
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: filled ? c.brand : c.surface,
          borderRadius: Radii.xlAll,
          border: filled ? null : Border.all(color: c.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: filled ? Colors.white.withValues(alpha: 0.18) : c.surfaceOverlay,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: filled ? c.onBrand : context.colors.primary),
            ),
            const SizedBox(height: Space.md),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleLarge?.copyWith(color: fg),
            ),
            Text(
              caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(color: filled ? c.onBrand.withValues(alpha: 0.8) : null),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rooms you host or joined, so you can get back into one after closing the
/// app without its code (it drops out of Live now once everyone has left, and
/// private rooms are never there). Hidden when you have none.
class _MyRooms extends ConsumerStatefulWidget {
  const _MyRooms();

  @override
  ConsumerState<_MyRooms> createState() => _MyRoomsState();
}

class _MyRoomsState extends ConsumerState<_MyRooms> {
  // Home stays alive in the tab stack, so a failed load would otherwise
  // stick until the app restarts: ask again whenever the user comes back.
  late final _lifecycle = AppLifecycleListener(
    onResume: () {
      if (ref.read(myRoomsProvider).hasError) ref.invalidate(myRoomsProvider);
    },
  );

  @override
  void initState() {
    super.initState();
    _lifecycle; // start listening
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _end(Room room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('End "${room.name}"?'),
        content: const Text('Everyone in it is sent out, and it can’t be reopened.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SynkPalette.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End room'),
          ),
        ],
      ),
    );
    if (!(ok ?? false) || !mounted) return;
    try {
      final session = ref.read(roomSessionProvider);
      if (session?.room.id == room.id) {
        await ref.read(roomSessionProvider.notifier).leave(endForAll: true);
      } else {
        await ref.read(roomRepositoryProvider).close(room.id);
        final uid = ref.read(currentProfileProvider)?.uid;
        if (uid != null) await ref.read(roomMemoryProvider).forget(uid, room.id);
      }
      ref
        ..invalidate(myRoomsProvider)
        ..invalidate(liveRoomsProvider);
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  Future<void> _remove(Room room) async {
    final uid = ref.read(currentProfileProvider)?.uid;
    if (uid == null) return;
    await ref.read(roomMemoryProvider).forget(uid, room.id);
    ref.invalidate(myRoomsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myRoomsProvider);
    final rooms = async.value ?? const <Room>[];
    final header = SectionHeader('Your rooms', accent: context.synk.accent);
    if (rooms.isEmpty && async.hasError) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: _LoadFailed(message: "Couldn't load your rooms", onRetry: () => ref.invalidate(myRoomsProvider)),
          ),
        ],
      );
    }
    if (rooms.isEmpty) return const SizedBox.shrink();
    final hereId = ref.watch(roomSessionProvider.select((s) => s?.room.id));
    final myUid = ref.watch(currentProfileProvider.select((p) => p?.uid));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        SizedBox(
          height: MediaQuery.textScalerOf(context).scale(56) + 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            itemCount: rooms.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (_, i) {
              final room = rooms[i];
              return MyRoomCard(
                room: room,
                here: room.id == hereId,
                onOpen: () => context.push(Routes.room(room.id)),
                onShare: () => SharePlus.instance.share(
                  ShareParams(
                    text:
                        'Listen with me on ${AppConfig.appName} 🎧\n'
                        'Room "${room.name}" — code ${room.code}\n${room.inviteLink}',
                  ),
                ),
                onEnd: room.hostId == myUid ? () => _end(room) : null,
                onRemove: room.hostId == myUid ? null : () => _remove(room),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One-line "couldn't load" row with a retry.
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.sm, Space.sm),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.xlAll,
        border: Border.all(color: c.glassBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: c.textSecondary),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(message, style: context.text.bodyMedium?.copyWith(color: c.textSecondary)),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Live rooms as swipeable tickets, with a page indicator.
class _LiveRoomsCarousel extends ConsumerStatefulWidget {
  const _LiveRoomsCarousel();

  @override
  ConsumerState<_LiveRoomsCarousel> createState() => _LiveRoomsCarouselState();
}

class _LiveRoomsCarouselState extends ConsumerState<_LiveRoomsCarousel> {
  static const double _height = 330;

  // A peek of the next card says "swipe".
  final _pages = PageController(viewportFraction: 0.9);
  final _page = ValueNotifier(0);

  @override
  void dispose() {
    _pages.dispose();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(liveRoomsProvider);
    final myUid = ref.watch(currentProfileProvider.select((p) => p?.uid));
    final hereId = ref.watch(roomSessionProvider.select((s) => s?.room.id));
    return rooms.when(
      skipLoadingOnRefresh: true,
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: Space.gutter),
        child: Skeleton(height: _height, radius: Radii.xlAll),
      ),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(liveRoomsProvider)),
      data: (all) {
        final list = othersLiveRooms(all, myUid: myUid, currentRoomId: hereId);
        if (list.isEmpty) return const _NoRoomsCard();
        return Column(
          children: [
            SizedBox(
              height: _height,
              child: PageView.builder(
                controller: _pages,
                padEnds: false,
                itemCount: list.length,
                onPageChanged: (i) => _page.value = i,
                itemBuilder: (_, i) => Padding(
                  padding: EdgeInsets.only(left: i == 0 ? Space.gutter : Space.sm / 2, right: Space.sm / 2),
                  child: RoomCard(room: list[i], height: _height),
                ),
              ),
            ),
            if (list.length > 1) ...[
              const SizedBox(height: Space.md),
              ValueListenableBuilder(
                valueListenable: _page,
                builder: (_, page, _) => SegmentIndicator(count: list.length.clamp(0, 8), index: page.clamp(0, 7)),
              ),
            ],
          ],
        );
      },
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
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: Radii.xlAll,
          border: Border.all(color: c.glassBorder),
        ),
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

/// Regional YouTube music chart (1 quota unit, cached 30 min): the top five
/// on a panel, the rest behind "See all".
class _TrendingVideos extends ConsumerWidget {
  const _TrendingVideos();

  static const _shown = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(youtubeEnabledProvider);
    final videos = enabled ? ref.watch(trendingVideosProvider) : null;
    final count = videos?.value?.length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Trending videos',
          action: count > _shown ? 'See all' : null,
          onAction: () => context.push(Routes.trending),
        ),
        if (videos == null)
          const _VideosDisabledCard()
        else
          videos.when(
            loading: () => const TrackListSkeleton(count: _shown),
            error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(trendingVideosProvider)),
            data: (list) {
              final top = list.take(_shown).toList();
              return TrackPanel(tracks: top, onTap: (i) => playTrackFromList(context, ref, list, i));
            },
          ),
      ],
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
        color: context.synk.surface,
        padding: const EdgeInsets.all(Space.lg),
        child: Row(
          children: [
            Icon(Icons.smart_display_rounded, color: context.colors.primary),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                kDebugMode
                    // A dev build started without the keys: say how to fix it.
                    ? 'YouTube is off: this build has no API key. Run with '
                          '--dart-define-from-file=env/dev.json (VS Code F5 does this).'
                    : 'Videos are coming soon to this build. Radio works right now.',
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

/// Horizontal rail of station cards.
class _TrackRail extends ConsumerWidget {
  const _TrackRail({required this.value, this.onRetry});

  final AsyncValue<List<Track>> value;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: TrackCard.railHeight(context),
      child: value.when(
        loading: () => ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          itemCount: 4,
          separatorBuilder: (_, _) => const SizedBox(width: Space.md),
          itemBuilder: (_, _) => const Align(
            alignment: Alignment.topCenter,
            child: Skeleton(width: TrackCard.width, height: TrackCard.width, radius: Radii.lgAll),
          ),
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

/// Every vibe as a solid colour pill with its icon and a chevron.
class _VibeGrid extends StatelessWidget {
  const _VibeGrid();

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: Space.md,
          crossAxisSpacing: Space.md,
          mainAxisExtent: MediaQuery.textScalerOf(context).scale(20) + 44,
        ),
        itemCount: Vibes.all.length,
        itemBuilder: (_, i) {
          final v = Vibes.all[i];
          return Pressable(
            onTap: () => context.push(Routes.genre(v.label)),
            semanticLabel: '${v.label} vibe',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm),
              decoration: BoxDecoration(borderRadius: Radii.pillAll, color: SynkPalette.identityColor(v.colorIndex)),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                    child: Icon(v.icon, size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      v.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall?.copyWith(color: Colors.white),
                    ),
                  ),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.25), shape: BoxShape.circle),
                    child: const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white),
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
