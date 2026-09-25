import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synk/features/rooms/application/room_providers.dart';
import 'package:synk/features/rooms/data/room_repository.dart';
import 'package:synk/features/rooms/domain/room.dart';

Room _room(String id) => Room(
  id: id,
  name: 'Room $id',
  code: 'ABC123',
  hostId: 'h',
  hostName: 'host',
  hostEmoji: '🎧',
  hostColor: 0,
  visibility: RoomVisibility.public,
  mode: RoomMode.music,
  capacity: 25,
  listenerCount: 3,
);

/// Serves [pages] in order; the cursor is just the index of the next page.
class _FakeDirectory {
  _FakeDirectory(this.pages);

  final List<Object> pages; // RoomPage-ish: List<String> ids, or an Exception
  final calls = <Object?>[];

  Future<RoomPage> load({Object? after, int limit = 20}) async {
    calls.add(after);
    final i = (after as int?) ?? 0;
    final page = pages[i];
    if (page is Exception) throw page;
    return RoomPage(
      rooms: [for (final id in page as List<String>) _room(id)],
      cursor: i + 1,
      hasMore: i + 1 < pages.length,
    );
  }
}

ProviderContainer _container(_FakeDirectory dir) {
  final c = ProviderContainer(overrides: [roomPageLoaderProvider.overrideWithValue(dir.load)]);
  addTearDown(c.dispose);
  c.listen(liveRoomsPagerProvider, (_, _) {}); // keep the autoDispose pager alive
  return c;
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('loads the first page on open, then more on demand, until the end', () async {
    final dir = _FakeDirectory([
      ['a', 'b'],
      ['c'],
    ]);
    final c = _container(dir);
    await _settle();
    expect(c.read(liveRoomsPagerProvider).rooms.map((r) => r.id), ['a', 'b']);
    expect(c.read(liveRoomsPagerProvider).hasMore, isTrue);

    await c.read(liveRoomsPagerProvider.notifier).loadMore();
    final s = c.read(liveRoomsPagerProvider);
    expect(s.rooms.map((r) => r.id), ['a', 'b', 'c']);
    expect(s.hasMore, isFalse);

    await c.read(liveRoomsPagerProvider.notifier).loadMore();
    expect(dir.calls, hasLength(2), reason: 'no request past the end');
  });

  test('a room that moved between pages is shown once', () async {
    final dir = _FakeDirectory([
      ['a', 'b'],
      ['b', 'c'],
    ]);
    final c = _container(dir);
    await _settle();
    await c.read(liveRoomsPagerProvider.notifier).loadMore();
    expect(c.read(liveRoomsPagerProvider).rooms.map((r) => r.id), ['a', 'b', 'c']);
  });

  test('pages that filter down to nothing are skipped automatically', () async {
    final dir = _FakeDirectory([
      <String>[],
      <String>[],
      ['z'],
    ]);
    final c = _container(dir);
    await _settle();
    await _settle();
    expect(c.read(liveRoomsPagerProvider).rooms.map((r) => r.id), ['z']);
  });

  test('an error keeps what was loaded and retry continues from there', () async {
    final dir = _FakeDirectory([
      ['a'],
      Exception('offline'),
    ]);
    final c = _container(dir);
    await _settle();
    await c.read(liveRoomsPagerProvider.notifier).loadMore();
    var s = c.read(liveRoomsPagerProvider);
    expect(s.rooms.map((r) => r.id), ['a']);
    expect(s.error, isNotNull);
    expect(s.loading, isFalse);

    dir.pages[1] = ['b'];
    await c.read(liveRoomsPagerProvider.notifier).loadMore();
    s = c.read(liveRoomsPagerProvider);
    expect(s.rooms.map((r) => r.id), ['a', 'b']);
    expect(s.error, isNull);
  });

  test('refresh starts over from the first page', () async {
    final dir = _FakeDirectory([
      ['a'],
      ['b'],
    ]);
    final c = _container(dir);
    await _settle();
    await c.read(liveRoomsPagerProvider.notifier).loadMore();
    await c.read(liveRoomsPagerProvider.notifier).refresh();
    expect(c.read(liveRoomsPagerProvider).rooms.map((r) => r.id), ['a']);
    expect(dir.calls.last, isNull, reason: 'first page has no cursor');
  });
}
