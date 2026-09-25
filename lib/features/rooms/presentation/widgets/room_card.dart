import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/design_system/design_system.dart';
import '../../../../core/utils/formatters.dart';
import '../../application/room_providers.dart';
import '../../domain/room.dart';

/// Live room "ticket" for the Home carousel: the song playing in it as a
/// violet-tinted poster, the room's name over it, and a solid band to join.
/// The notches where poster meets band are two discs in the page colour.
class RoomCard extends StatelessWidget {
  const RoomCard({required this.room, this.height = 330, super.key});

  final Room room;
  final double height;

  static const double _band = 56;
  static const double _notch = 9;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    final np = room.nowPlaying;
    final tint = room.coverColor.isEven ? c.brand : SynkPalette.identityColor(room.coverColor);

    return Pressable(
      scale: 0.98,
      onTap: () => context.push(Routes.room(room.id)),
      semanticLabel:
          '${room.name}, ${room.listenerCount} listening, hosted by ${room.hostName}'
          '${np == null ? '' : ', playing ${np.title}'}. Join room',
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: Radii.xlAll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        LayoutBuilder(
                          builder: (_, box) => DuotoneCover(
                            url: np?.artworkUrl,
                            color: tint,
                            decodeWidth: box.maxWidth,
                            icon: room.mode == RoomMode.radio ? Icons.radio_rounded : Icons.graphic_eq_rounded,
                          ),
                        ),
                        Positioned(
                          left: Space.md,
                          top: Space.md,
                          right: Space.md,
                          child: Row(
                            children: [
                              LiveBadge(count: room.listenerCount, compact: true),
                              const Spacer(),
                              RoomListenersPreview(room: room, size: 24),
                            ],
                          ),
                        ),
                        Positioned(
                          left: Space.lg,
                          right: Space.lg,
                          bottom: Space.lg,
                          child: Column(
                            children: [
                              Text(
                                room.mode == RoomMode.radio ? 'Radio room' : 'Listening room',
                                style: context.text.labelSmall?.copyWith(color: Colors.white70, letterSpacing: 1),
                              ),
                              const SizedBox(height: Space.xs),
                              Text(
                                room.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: context.text.headlineMedium?.copyWith(color: Colors.white),
                              ),
                              const SizedBox(height: Space.sm),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (np != null) ...[
                                    const EqualizerBars(color: Colors.white, size: 10),
                                    const SizedBox(width: 6),
                                  ],
                                  Flexible(
                                    child: Text(
                                      np == null ? 'Picking the first song…' : '${np.title} · ${np.artist}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.text.bodySmall?.copyWith(color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    height: _band,
                    color: c.brand,
                    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                    child: Row(
                      children: [
                        Icon(Icons.headphones_rounded, color: c.onBrand, size: 20),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: Text(
                            '@${room.hostName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelLarge?.copyWith(color: c.onBrand),
                          ),
                        ),
                        Text('Join', style: context.text.labelLarge?.copyWith(color: c.onBrand)),
                        const SizedBox(width: Space.xs),
                        Icon(Icons.arrow_forward_rounded, color: c.onBrand, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Ticket notches.
            for (final left in [true, false])
              Positioned(
                left: left ? -_notch : null,
                right: left ? null : -_notch,
                bottom: _band - _notch,
                child: Container(
                  width: _notch * 2,
                  height: _notch * 2,
                  decoration: BoxDecoration(color: c.background, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Who's in [room]: the first few avatars plus "+N". Shows the host until the
/// preview arrives, so the row never jumps.
class RoomListenersPreview extends ConsumerWidget {
  const RoomListenersPreview({required this.room, this.size = 24, super.key});

  final Room room;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(roomListenersPreviewProvider(room.id)).value;
    final avatars = members == null || members.isEmpty
        ? [(emoji: room.hostEmoji, colorIndex: room.hostColor)]
        : [for (final m in members) (emoji: m.emoji, colorIndex: m.color)];
    return ExcludeSemantics(
      child: AvatarStack(avatars: avatars, total: math.max(room.listenerCount, avatars.length), size: size),
    );
  }
}

/// Wide row for the Live now list: tinted cover, name, what's playing, who's in.
class RoomTile extends StatelessWidget {
  const RoomTile({required this.room, super.key});

  final Room room;

  static const double _cover = 88;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    final np = room.nowPlaying;
    return Pressable(
      scale: 0.98,
      onTap: () => context.push(Routes.room(room.id)),
      semanticLabel:
          '${room.name}, ${room.listenerCount} listening, hosted by ${room.hostName}'
          '${np == null ? '' : ', playing ${np.title}'}',
      child: Container(
        padding: const EdgeInsets.all(Space.sm),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: Radii.xlAll,
          border: Border.all(color: c.glassBorder),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: Radii.lgAll,
              child: SizedBox.square(
                dimension: _cover,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DuotoneCover(
                      url: np?.artworkUrl,
                      color: room.coverColor.isEven ? c.brand : SynkPalette.identityColor(room.coverColor),
                      decodeWidth: _cover,
                      icon: room.mode == RoomMode.radio ? Icons.radio_rounded : Icons.graphic_eq_rounded,
                    ),
                    const Positioned(left: 6, top: 6, child: LiveBadge(compact: true)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                  const SizedBox(height: Space.xs),
                  Row(
                    children: [
                      if (np != null) ...[
                        EqualizerBars(size: 10, color: context.colors.tertiary),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          np != null
                              ? '${np.title} · ${np.artist}'
                              : (room.mode == RoomMode.radio ? 'Radio room' : 'Picking the first song…'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  Row(
                    children: [
                      RoomListenersPreview(room: room, size: 22),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          '${Formatters.compact(room.listenerCount)} listening · @${room.hostName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelSmall?.copyWith(color: c.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.xs),
            Icon(Icons.chevron_right_rounded, color: c.textMuted),
          ],
        ),
      ),
    );
  }
}

/// A room you host, on Home → Your rooms: live, or paused until you're back.
/// Tap to (re)open it; the menu shares or ends it.
class MyRoomCard extends StatelessWidget {
  const MyRoomCard({
    required this.room,
    required this.here,
    required this.onOpen,
    required this.onShare,
    required this.onEnd,
    super.key,
  });

  final Room room;

  /// You're in this room right now.
  final bool here;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onEnd;

  static const double width = 272;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    final active = room.isActive();
    final (status, statusColor) = here
        ? ("You're in it", context.colors.primary)
        : active
        ? ('Live · ${Formatters.compact(room.listenerCount)} listening', c.live)
        : ('Paused · tap to open', c.textSecondary);
    final np = room.nowPlaying;

    return SizedBox(
      width: width,
      child: Pressable(
        scale: 0.98,
        onTap: onOpen,
        semanticLabel: '${room.name}, $status. Open room',
        child: Container(
          padding: const EdgeInsets.all(Space.sm),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: Radii.xlAll,
            border: Border.all(color: here ? context.colors.primary : c.glassBorder),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: Radii.lgAll,
                child: SizedBox.square(
                  dimension: 64,
                  child: DuotoneCover(
                    url: np?.artworkUrl,
                    color: SynkPalette.identityColor(room.coverColor),
                    decodeWidth: 64,
                    icon: room.mode == RoomMode.radio ? Icons.radio_rounded : Icons.graphic_eq_rounded,
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(room.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (!room.isPublic) ...[
                          Icon(Icons.lock_rounded, size: 12, color: c.textSecondary),
                          const SizedBox(width: 4),
                        ],
                        Text(room.code, style: context.text.labelSmall?.copyWith(letterSpacing: 1.5)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(color: statusColor),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Room options',
                icon: Icon(Icons.more_vert_rounded, color: c.textSecondary),
                onSelected: (v) => v == 'end' ? onEnd() : onShare(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'share', child: Text('Invite friends')),
                  PopupMenuItem(
                    value: 'end',
                    child: Text('End room for everyone', style: TextStyle(color: SynkPalette.danger)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
