import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../catalog/domain/track.dart';
import '../../rooms/application/room_session_controller.dart';
import 'player_providers.dart';

/// One rule for "the user tapped a song", used by every list:
/// * in a room → it goes to the room (play or queue);
/// * radio → plays solo in the background;
/// * YouTube → plays solo and opens the player, because a video only plays while
///   its official player is on screen.
Future<void> playTrackFromList(BuildContext context, WidgetRef ref, List<Track> list, int index) async {
  final track = list[index];
  final router = GoRouter.of(context);
  final inRoom = ref.read(roomSessionProvider) != null;
  try {
    if (inRoom) {
      await ref.read(roomSessionProvider.notifier).playOrQueue(track);
      if (context.mounted) context.showSnack('Sent to the room', icon: Icons.queue_music_rounded);
    } else if (track.isLive) {
      await ref.read(soloPlayerProvider.notifier).playOne(track);
    } else {
      // Queue the rest of the videos so "next" works like people expect.
      final videos = list.where((t) => t.isYouTube).toList();
      await ref
          .read(soloPlayerProvider.notifier)
          .playTracks(videos, startIndex: videos.indexOf(track).clamp(0, videos.length - 1));
      await router.push(Routes.player);
    }
  } catch (e) {
    if (context.mounted) context.showError(e);
  }
}
