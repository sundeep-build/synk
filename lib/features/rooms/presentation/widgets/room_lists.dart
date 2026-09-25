import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/utils/formatters.dart';
import '../../../catalog/domain/track.dart';
import '../../../catalog/presentation/track_widgets.dart';
import '../../../player/presentation/track_actions_sheet.dart';
import '../../application/room_providers.dart';
import '../../application/room_session_controller.dart';
import '../../domain/room.dart';
import '../../domain/room_live_models.dart';

/// Now playing → Up next → Played. A track never just vanishes: when it
/// starts it moves to the top, when it ends it moves to Played.
class RoomQueueView extends ConsumerWidget {
  const RoomQueueView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (current, playingItem, upcoming, played) = ref.watch(
      roomSessionProvider.select(
        (s) => (s?.playback.track, s?.playingItem, s?.upcoming ?? const <QueueItem>[], s?.played ?? const <Track>[]),
      ),
    );
    final (canControl, myUid, radio) = ref.watch(
      roomSessionProvider.select((s) => (s?.canControl ?? false, s?.myUid, s?.room.mode == RoomMode.radio)),
    );
    final history = [
      for (final t in played)
        if (t.id != current?.id) t,
    ];

    if (current == null && upcoming.isEmpty && history.isEmpty) {
      return Center(
        child: EmptyState(
          icon: Icons.queue_music_rounded,
          title: 'Queue is empty',
          message: radio
              ? 'Radio rooms play one station at a time.'
              : "Add songs from search. When it runs dry we'll keep the vibe going with similar tracks.",
        ),
      );
    }

    final controller = ref.read(roomSessionProvider.notifier);
    return ListView(
      padding: const EdgeInsets.only(bottom: Space.lg),
      children: [
        if (current != null) ...[
          const _QueueLabel('Now playing'),
          TrackTile(
            key: const ValueKey('now-playing'),
            track: current,
            highlight: true,
            subtitle: playingItem == null ? null : '${current.artist} · added by @${playingItem.addedByName}',
            onTap: () => showTrackActions(context, current),
          ),
        ],
        if (!radio || upcoming.isNotEmpty) ...[
          const _QueueLabel('Up next'),
          if (upcoming.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.sm),
              child: Text(
                "Nothing queued — we'll keep the vibe going with similar tracks.",
                style: context.text.bodySmall,
              ),
            ),
          for (final item in upcoming)
            TrackTile(
              key: ValueKey(item.id),
              track: item.track,
              highlight: false,
              subtitle: '${item.track.artist} · added by @${item.addedByName}',
              // Controllers tap to play it now; everyone else gets the actions sheet.
              onTap: canControl
                  ? () => controller.playNow(item).catchError((Object e) {
                      if (context.mounted) context.showError(e);
                    })
                  : () => showTrackActions(context, item.track),
              trailing: canControl || item.addedBy == myUid
                  ? IconButton(
                      tooltip: 'Remove from queue',
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      onPressed: () => controller.removeFromQueue(item).catchError((Object e) {
                        if (context.mounted) context.showError(e);
                      }),
                    )
                  : const SizedBox(width: 48),
            ),
        ],
        if (history.isNotEmpty) ...[
          const _QueueLabel('Played'),
          for (final (i, t) in history.indexed)
            TrackTile(
              key: ValueKey('played:${t.id}:$i'),
              track: t,
              highlight: false,
              onTap: () => showTrackActions(context, t),
            ),
        ],
      ],
    );
  }
}

class _QueueLabel extends StatelessWidget {
  const _QueueLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xs),
    child: Semantics(
      header: true,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 12,
            decoration: BoxDecoration(color: context.colors.tertiary, borderRadius: Radii.pillAll),
          ),
          const SizedBox(width: Space.sm),
          Text(
            label.toUpperCase(),
            style: context.text.labelSmall?.copyWith(color: context.synk.textSecondary, letterSpacing: 1.4),
          ),
        ],
      ),
    ),
  );
}

/// Who's in the room, and who joined but is away, opened from the people
/// chip in the room header or the room's ⋮ menu (All members).
Future<void> showRoomPeople(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (sheet) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.7),
    child: const _PeopleSheet(),
  ),
);

class _PeopleSheet extends StatelessWidget {
  const _PeopleSheet();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, 0),
          child: Text('People', style: context.text.titleLarge),
        ),
        const Flexible(child: RoomMembersView(shrinkWrap: true)),
      ],
    ),
  );
}

/// Everyone in the room now, in join order, then everyone who joined and
/// hasn't left on purpose but is away (app closed, offline), most recently
/// seen first.
class RoomMembersView extends ConsumerWidget {
  const RoomMembersView({this.shrinkWrap = false, super.key});

  /// Size to the list (inside a sheet) instead of filling the parent.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(roomSessionProvider.select((s) => s?.members ?? const <RoomMember>[]));
    final (roomId, hostId, myUid, leader) = ref.watch(
      roomSessionProvider.select((s) => (s?.room.id, s?.room.hostId, s?.myUid, s?.leaderUid)),
    );
    final roster = roomId == null ? null : ref.watch(roomRosterProvider(roomId)).value;
    final here = {for (final m in members) m.uid};
    final away = [
      for (final r in roster ?? const <RosterEntry>[])
        if (!here.contains(r.uid)) r,
    ]..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    final hostAway = !here.contains(hostId);
    final now = ref.read(serverClockProvider).nowMs();
    String name(String uid, String name) => uid == myUid ? '$name (you)' : name;

    return ListView(
      shrinkWrap: shrinkWrap,
      padding: const EdgeInsets.only(bottom: Space.sm),
      children: [
        _SectionLabel('In the room · ${members.length}'),
        for (final m in members)
          _PersonTile(
            emoji: m.emoji,
            color: m.color,
            name: name(m.uid, m.name),
            badge: m.uid == hostId
                ? 'HOST'
                : hostAway && m.uid == leader
                ? 'ACTING HOST'
                : null,
          ),
        if (away.isNotEmpty) ...[
          _SectionLabel('Away · ${away.length}'),
          for (final r in away)
            _PersonTile(
              emoji: r.emoji,
              color: r.color,
              name: name(r.uid, r.name),
              badge: r.uid == hostId ? 'HOST' : null,
              lastSeen: _lastSeen(r.lastSeen, now),
            ),
        ],
      ],
    );
  }

  static String _lastSeen(int lastSeenMs, int nowMs) {
    final ago = Formatters.timeAgo(
      DateTime.fromMillisecondsSinceEpoch(lastSeenMs),
      DateTime.fromMillisecondsSinceEpoch(nowMs),
    );
    return ago == 'now' ? 'Last seen just now' : 'Last seen $ago ago';
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xs),
    child: Text(text, style: context.text.labelLarge?.copyWith(color: context.synk.textSecondary)),
  );
}

/// One person: in the room, or away (dimmed, with when they were last in).
class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.emoji, required this.color, required this.name, this.badge, this.lastSeen});

  final String emoji;
  final int color;
  final String name;
  final String? badge;

  /// Set for people who are away.
  final String? lastSeen;

  @override
  Widget build(BuildContext context) {
    final away = lastSeen != null;
    return ListTile(
      leading: Opacity(
        opacity: away ? 0.45 : 1,
        child: SynkAvatar(emoji: emoji, colorIndex: color, size: 40, ring: badge != null && !away),
      ),
      title: Text(name, style: away ? TextStyle(color: context.synk.textSecondary) : null),
      subtitle: away ? Text(lastSeen!) : null,
      trailing: badge == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
              decoration: BoxDecoration(color: context.colors.primaryContainer, borderRadius: Radii.pillAll),
              child: Text(badge!, style: context.text.labelSmall?.copyWith(color: context.colors.onPrimaryContainer)),
            ),
    );
  }
}
