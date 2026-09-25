import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/logging/app_logger.dart';
import '../../auth/application/session.dart';
import '../data/room_live_datasource.dart';
import '../data/room_repository.dart';
import '../domain/room.dart';
import '../domain/room_live_models.dart';
import '../sync/server_clock.dart';

final roomRepositoryProvider = Provider<RoomRepository>(
  (ref) => RoomRepository(ref.watch(firestoreProvider), ref.watch(databaseProvider)),
);

final roomLiveProvider = Provider<RoomLiveDataSource>((ref) => RoomLiveDataSource(ref.watch(databaseProvider)));

final serverClockProvider = Provider<ServerClock>((ref) {
  final clock = ServerClock(ref.watch(databaseProvider));
  ref.onDispose(clock.dispose);
  return clock;
});

/// Public live rooms for Home. One-shot query cached for 60s after the last
/// listener leaves; pull-to-refresh invalidates it.
final liveRoomsProvider = FutureProvider.autoDispose<List<Room>>((ref) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(seconds: 60), link.close);
  ref.onDispose(timer.cancel);
  return ref.watch(roomRepositoryProvider).liveRooms();
});

/// Rooms you host that haven't been ended (Home → Your rooms), so you can
/// reopen one after closing the app. One small query, cached for 60s.
final myRoomsProvider = FutureProvider.autoDispose<List<Room>>((ref) async {
  final uid = ref.watch(currentProfileProvider.select((p) => p?.uid));
  if (uid == null) return const [];
  final link = ref.keepAlive();
  final timer = Timer(const Duration(seconds: 60), link.close);
  ref.onDispose(timer.cancel);
  try {
    return await ref.watch(roomRepositoryProvider).hostedBy(uid);
  } catch (e, st) {
    AppLogger.error('MyRooms', e, st);
    rethrow;
  }
});

/// First few people in a room, for the avatar stacks on Home and Live now.
/// One small indexed read per room, cached for 60s like the directory.
final roomListenersPreviewProvider = FutureProvider.autoDispose.family<List<RoomMember>, String>((ref, roomId) {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(seconds: 60), link.close);
  ref.onDispose(timer.cancel);
  return ref.watch(roomLiveProvider).presencePreview(roomId);
});

/// Loads one page of the live-room directory (a seam so the pager is testable).
typedef RoomPageLoader = Future<RoomPage> Function({Object? after, int limit});

final roomPageLoaderProvider = Provider<RoomPageLoader>((ref) => ref.watch(roomRepositoryProvider).liveRoomsPage);

@immutable
class LiveRoomsState {
  const LiveRoomsState({this.rooms = const [], this.hasMore = true, this.loading = false, this.error});

  final List<Room> rooms;
  final bool hasMore;
  final bool loading;
  final Object? error;

  LiveRoomsState copyWith({List<Room>? rooms, bool? hasMore, bool? loading, Object? Function()? error}) =>
      LiveRoomsState(
        rooms: rooms ?? this.rooms,
        hasMore: hasMore ?? this.hasMore,
        loading: loading ?? this.loading,
        error: error == null ? this.error : error(),
      );
}

/// "Live now → View all": every public live room, busiest first, a page at a time.
final liveRoomsPagerProvider = NotifierProvider.autoDispose<LiveRoomsPager, LiveRoomsState>(LiveRoomsPager.new);

class LiveRoomsPager extends Notifier<LiveRoomsState> {
  static const pageSize = 20;

  /// A page can come back empty after filtering; skip ahead at most this many.
  static const _maxEmptySkips = 3;

  Object? _cursor;
  int _generation = 0;

  @override
  LiveRoomsState build() {
    Future.microtask(loadMore);
    return const LiveRoomsState();
  }

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    final generation = _generation;
    state = state.copyWith(loading: true, error: () => null);
    try {
      final load = ref.read(roomPageLoaderProvider);
      var rooms = state.rooms;
      var hasMore = true;
      for (var attempt = 0; attempt <= _maxEmptySkips && hasMore; attempt++) {
        final page = await load(after: _cursor, limit: pageSize);
        if (!ref.mounted || generation != _generation) return;
        _cursor = page.cursor;
        hasMore = page.hasMore;
        // Counts move while paging, so a room can show up twice: keep the first.
        final seen = {for (final r in rooms) r.id};
        final fresh = [
          for (final r in page.rooms)
            if (seen.add(r.id)) r,
        ];
        rooms = [...rooms, ...fresh];
        if (fresh.isNotEmpty) break;
      }
      state = LiveRoomsState(rooms: rooms, hasMore: hasMore);
    } catch (e) {
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(loading: false, error: () => e);
    }
  }

  Future<void> refresh() async {
    _generation++;
    _cursor = null;
    state = const LiveRoomsState();
    await loadMore();
  }
}

/// Chat for one room: last page on open, then live appends. Capped in memory
/// and torn down when the room screen isn't visible (saves bandwidth too).
final roomChatProvider = NotifierProvider.autoDispose.family<RoomChatController, List<ChatMessage>, String>(
  RoomChatController.new,
);

class RoomChatController extends Notifier<List<ChatMessage>> {
  RoomChatController(this.roomId);

  final String roomId;

  @override
  List<ChatMessage> build() {
    final sub = ref
        .watch(roomLiveProvider)
        .chat(roomId)
        .listen(_append, onError: (Object e, StackTrace st) => AppLogger.error('Chat', e, st));
    ref.onDispose(sub.cancel);
    return const [];
  }

  void _append(ChatMessage m) {
    final next = [...state, m];
    final overflow = next.length - AppConfig.chatMemoryCap;
    state = overflow > 0 ? next.sublist(overflow) : next;
  }
}

/// Emoji bursts sent after the screen opened (never replays old ones).
final roomReactionsProvider = StreamProvider.autoDispose.family<Reaction, String>((ref, roomId) {
  final since = ref.read(serverClockProvider).nowMs();
  return ref.watch(roomLiveProvider).reactions(roomId, sinceServerMs: since);
});
