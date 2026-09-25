import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/router/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/utils/formatters.dart';
import '../application/room_providers.dart';
import '../application/room_session_controller.dart';
import '../domain/room.dart';
import 'widgets/huddle_bar.dart';
import 'widgets/reaction_layer.dart';
import 'widgets/room_chat.dart';
import 'widgets/room_lists.dart';
import 'widgets/room_now_playing.dart';

class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({required this.roomId, super.key});

  final String roomId;

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    _join();
  }

  void _join() {
    final s = ref.read(roomSessionProvider);
    if (s != null && s.room.id == widget.roomId && !s.ended) return;
    setState(() => _error = null);
    ref.read(roomSessionProvider.notifier).join(widget.roomId).catchError((Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final (id, ended) = ref.watch(roomSessionProvider.select((s) => (s?.room.id, s?.ended ?? false)));

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: Center(
          child: ErrorState(error: _error!, onRetry: _join),
        ),
      );
    }
    if (id != widget.roomId) {
      return Scaffold(
        body: AuroraBackground(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const EqualizerBars(size: 40, bars: 5),
                const SizedBox(height: Space.lg),
                Text('Tuning in…', style: context.text.titleLarge),
              ],
            ),
          ),
        ),
      );
    }
    if (ended) return const _RoomEnded();
    return const _RoomBody();
  }
}

class _RoomBody extends ConsumerStatefulWidget {
  const _RoomBody();

  @override
  ConsumerState<_RoomBody> createState() => _RoomBodyState();
}

class _RoomBodyState extends ConsumerState<_RoomBody> {
  /// Below this screen height (small phones, split screen) the player is
  /// compact even without the keyboard, so the chat keeps some room.
  static const double _compactPlayerBelow = 720;

  final _reactions = GlobalKey<ReactionLayerState>();

  @override
  Widget build(BuildContext context) {
    // Selectors must tolerate null: the session is cleared the moment the
    // user leaves, a frame before this screen is popped.
    final room = ref.watch(roomSessionProvider.select((s) => s?.room));
    final myUid = ref.watch(roomSessionProvider.select((s) => s?.myUid));
    final art = ref.watch(roomSessionProvider.select((s) => s?.playback.track?.artworkUrl));
    final queueCount = ref.watch(roomSessionProvider.select((s) => s?.upcoming.length ?? 0));
    final memberCount = ref.watch(roomSessionProvider.select((s) => s?.members.length ?? 0));
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final compactPlayer = keyboardOpen || MediaQuery.sizeOf(context).height < _compactPlayerBelow;
    if (room == null || myUid == null) return const SizedBox.shrink();

    // Keep the chat stream subscribed while the room is open, even when the
    // Chat tab is off-screen (TabBarView disposes it) — no re-downloads.
    ref.listen(roomChatProvider(room.id), (_, _) {});

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: AmbientBackdrop(
          url: art,
          child: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                Column(
                  children: [
                    _RoomHeader(room: room, listeners: memberCount),
                    // Tucked away while typing: the chat needs the height, and the
                    // header's huddle button still opens the call.
                    AnimatedSize(
                      duration: Motion.medium,
                      curve: Motion.emphasized,
                      child: keyboardOpen ? const SizedBox(width: double.infinity) : HuddleBar(roomId: room.id),
                    ),
                    AnimatedSize(
                      duration: Motion.medium,
                      curve: Motion.emphasized,
                      child: RoomNowPlaying(compact: compactPlayer),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 0),
                      child: GlassPanel(
                        radius: Radii.pillAll,
                        padding: const EdgeInsets.all(4),
                        child: TabBar(
                          tabs: [
                            // Single-line labels: counts grow ("Queue · 42") and must not wrap.
                            for (final label in ['Chat', queueCount == 0 ? 'Queue' : 'Queue · $queueCount'])
                              Tab(
                                height: 36,
                                child: Text(label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          RoomChatView(roomId: room.id, myUid: myUid),
                          const RoomQueueView(),
                        ],
                      ),
                    ),
                    RoomComposer(
                      radio: room.mode == RoomMode.radio,
                      onLocalReaction: (e) => _reactions.currentState?.spawn(e),
                    ),
                  ],
                ),
                Positioned(
                  right: 0,
                  bottom: 120,
                  width: 120,
                  height: 360,
                  child: ReactionLayer(key: _reactions, roomId: room.id, myUid: myUid),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomHeader extends ConsumerWidget {
  const _RoomHeader({required this.room, required this.listeners});

  final Room room;
  final int listeners;

  Future<void> _share() => SharePlus.instance.share(
    ShareParams(
      text:
          'Listen with me on ${AppConfig.appName} 🎧\n'
          'Room "${room.name}" — code ${room.code}\n${room.inviteLink}',
    ),
  );

  void _copyCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: room.code));
    context.showSnack('Room code copied', icon: Icons.copy_rounded);
  }

  Future<void> _leave(BuildContext context, WidgetRef ref, {required bool endForAll}) async {
    final router = GoRouter.of(context);
    await ref.read(roomSessionProvider.notifier).leave(endForAll: endForAll);
    router.go(Routes.home);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHost = ref.watch(roomSessionProvider.select((s) => s?.isHost ?? false));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xs, Space.xs, Space.xs, Space.md),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Minimise (keeps playing)',
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
            onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(room.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleLarge),
                const SizedBox(height: Space.xs),
                Row(
                  children: [
                    const LiveBadge(compact: true),
                    const SizedBox(width: Space.sm),
                    Semantics(
                      button: true,
                      label: 'Copy room code ${room.code.split('').join(' ')}',
                      onTap: () => _copyCode(context),
                      excludeSemantics: true,
                      child: InkWell(
                        borderRadius: Radii.pillAll,
                        onTap: () => _copyCode(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 3),
                          decoration: BoxDecoration(
                            border: Border.all(color: context.synk.glassBorder),
                            borderRadius: Radii.pillAll,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!room.isPublic) ...[
                                Icon(Icons.lock_rounded, size: 12, color: context.synk.textSecondary),
                                const SizedBox(width: 4),
                              ],
                              Text(room.code, style: context.text.labelSmall?.copyWith(letterSpacing: 2)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const HuddleHeaderButton(),
          _PeopleChip(count: listeners),
          PopupMenuButton<String>(
            tooltip: 'Room options',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) => switch (v) {
              'share' => _share(),
              'code' => _copyCode(context),
              'leave' => _leave(context, ref, endForAll: false),
              'end' => _leave(context, ref, endForAll: true),
              _ => null,
            },
            itemBuilder: (_) => [
              _menuItem('share', Icons.ios_share_rounded, 'Invite friends'),
              _menuItem('code', Icons.copy_rounded, 'Copy room code'),
              const PopupMenuDivider(),
              _menuItem('leave', Icons.logout_rounded, 'Leave room'),
              if (isHost)
                _menuItem('end', Icons.stop_circle_outlined, 'End room for everyone', color: SynkPalette.danger),
            ],
          ),
        ],
      ),
    );
  }
}

PopupMenuItem<String> _menuItem(String value, IconData icon, String label, {Color? color}) => PopupMenuItem(
  value: value,
  child: Row(
    children: [
      Icon(icon, size: 20, color: color),
      const SizedBox(width: Space.md),
      Text(label, style: color == null ? null : TextStyle(color: color)),
    ],
  ),
);

/// Live head-count; tap to see who's here.
class _PeopleChip extends StatelessWidget {
  const _PeopleChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    return Semantics(
      button: true,
      label: '$count ${count == 1 ? 'person' : 'people'} here. Show people',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: Radii.pillAll,
        onTap: () => showRoomPeople(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 6),
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            border: Border.all(color: c.glassBorder),
            borderRadius: Radii.pillAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_alt_rounded, size: 18, color: context.colors.primary),
              const SizedBox(width: 6),
              Text(Formatters.compact(count), style: context.text.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomEnded extends ConsumerWidget {
  const _RoomEnded();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: AuroraBackground(
        child: Center(
          child: EmptyState(
            icon: Icons.nightlife_rounded,
            title: 'That was a vibe',
            message: 'The host ended this room.',
            action: PrimaryButton(
              label: 'Find another room',
              expand: false,
              onPressed: () {
                ref.read(roomSessionProvider.notifier).dismissEnded();
                context.go(Routes.home);
              },
            ),
          ),
        ),
      ),
    );
  }
}
