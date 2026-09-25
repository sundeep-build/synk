import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../application/room_providers.dart';
import 'room_sheets.dart';
import 'widgets/room_card.dart';

/// Home → Live now → View all: every public live room, busiest first, loading
/// the next page as the user nears the end.
class LiveRoomsScreen extends ConsumerStatefulWidget {
  const LiveRoomsScreen({super.key});

  @override
  ConsumerState<LiveRoomsScreen> createState() => _LiveRoomsScreenState();
}

class _LiveRoomsScreenState extends ConsumerState<LiveRoomsScreen> {
  final _scroll = ScrollController();

  /// Start the next page this far before the end, so scrolling rarely waits.
  static const _prefetchExtent = 600.0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < _prefetchExtent) ref.read(liveRoomsPagerProvider.notifier).loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(roomListenersPreviewProvider);
    await ref.read(liveRoomsPagerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(liveRoomsPagerProvider);
    final pager = ref.read(liveRoomsPagerProvider.notifier);
    final bottom = MediaQuery.paddingOf(context).bottom + Space.xl;

    // Every state is scrollable, so pull-to-refresh always works.
    Widget message(Widget child) => ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: bottom),
      children: [child],
    );

    final Widget body;
    if (s.rooms.isEmpty && s.error != null) {
      body = message(ErrorState(error: s.error!, onRetry: pager.loadMore));
    } else if (s.rooms.isEmpty && !s.hasMore) {
      body = message(
        EmptyState(
          icon: Icons.nightlife_rounded,
          title: 'No public rooms right now',
          message: 'Start one — people browsing Live now will see it.',
          action: PrimaryButton(
            label: 'Start a room',
            icon: Icons.sensors_rounded,
            expand: false,
            onPressed: () => showCreateRoomSheet(context),
          ),
        ),
      );
    } else if (s.rooms.isEmpty) {
      body = ListView.separated(
        padding: EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, bottom),
        itemCount: 5,
        separatorBuilder: (_, _) => const SizedBox(height: Space.md),
        itemBuilder: (_, _) => const Skeleton(height: 108, radius: Radii.xlAll),
      );
    } else {
      body = ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, bottom),
        itemCount: s.rooms.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: Space.md),
        itemBuilder: (_, i) =>
            i < s.rooms.length ? RoomTile(key: ValueKey(s.rooms[i].id), room: s.rooms[i]) : _Footer(state: s),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const CircleBackButton(),
        title: SplitTitle('Live now', style: context.text.headlineSmall),
      ),
      body: RefreshIndicator(onRefresh: _refresh, child: body),
    );
  }
}

/// End of the list: spinner while a page loads, retry on error, or "that's
/// everyone". Reaching it also asks for the next page, for lists too short to
/// scroll.
class _Footer extends ConsumerWidget {
  const _Footer({required this.state});

  final LiveRoomsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pager = ref.read(liveRoomsPagerProvider.notifier);
    if (state.hasMore && !state.loading && state.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => pager.loadMore());
    }
    final Widget child;
    if (state.error != null) {
      child = TextButton.icon(
        onPressed: pager.loadMore,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text("Couldn't load more · Retry"),
      );
    } else if (state.hasMore) {
      child = const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 2.5));
    } else {
      child = Text(
        "That's everyone live right now",
        style: context.text.bodySmall?.copyWith(color: context.synk.textMuted),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.lg),
      child: Center(child: child),
    );
  }
}
