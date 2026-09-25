import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/design_system/design_system.dart';
import '../../../../core/utils/formatters.dart';
import '../../application/room_providers.dart';
import '../../domain/room.dart';

/// Live room poster for the Home carousel: a solid cover block (artwork over
/// the room's colour) on top, a solid info panel below. Flat — no fades; the
/// cover gives way when large text needs more room.
class RoomCard extends StatelessWidget {
  const RoomCard({required this.room, this.width = 232, super.key});

  final Room room;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    final np = room.nowPlaying;

    return Pressable(
      onTap: () => context.push(Routes.room(room.id)),
      semanticLabel:
          '${room.name}, ${room.listenerCount} listening'
          '${np == null ? '' : ', playing ${np.title}'}',
      child: Container(
        width: width,
        height: width * 1.2,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: Radii.xlAll,
          border: Border.all(color: c.glassBorder, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: SynkPalette.identityColor(room.coverColor)),
                  if (np?.artworkUrl != null) Artwork(url: np!.artworkUrl, size: width, radius: BorderRadius.zero),
                  Positioned(
                    left: Space.md,
                    top: Space.md,
                    right: Space.md,
                    child: Row(
                      children: [
                        LiveBadge(count: room.listenerCount, compact: true),
                        const Spacer(),
                        if (room.mode == RoomMode.radio) const Icon(Icons.radio_rounded, color: Colors.white, size: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                  if (np != null) ...[
                    const SizedBox(height: Space.xs),
                    Row(
                      children: [
                        EqualizerBars(color: context.colors.primary, size: 10),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${np.title} · ${np.artist}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: Space.sm),
                  Row(
                    children: [
                      RoomListenersPreview(room: room, size: 22),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          '@${room.hostName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelMedium?.copyWith(color: c.textSecondary),
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

/// Wide row for the Live now list: cover, name, what's playing, who's in.
class RoomTile extends StatelessWidget {
  const RoomTile({required this.room, super.key});

  final Room room;

  static const double _cover = 88;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    final np = room.nowPlaying;
    return Pressable(
      onTap: () => context.push(Routes.room(room.id)),
      semanticLabel:
          '${room.name}, ${room.listenerCount} listening, hosted by ${room.hostName}'
          '${np == null ? '' : ', playing ${np.title}'}',
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: Radii.lgAll,
          border: Border.all(color: c.glassBorder, width: 0.8),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: Radii.mdAll,
              child: SizedBox.square(
                dimension: _cover,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: SynkPalette.identityColor(room.coverColor)),
                    if (np?.artworkUrl != null) Artwork(url: np!.artworkUrl, size: _cover, radius: BorderRadius.zero),
                    if (room.mode == RoomMode.radio && np?.artworkUrl == null)
                      const Icon(Icons.radio_rounded, color: Colors.white70, size: 32),
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
                        EqualizerBars(size: 10, color: context.colors.primary),
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
          ],
        ),
      ),
    );
  }
}
