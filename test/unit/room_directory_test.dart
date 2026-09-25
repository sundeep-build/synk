import 'package:flutter_test/flutter_test.dart';
import 'package:synk/features/rooms/domain/room.dart';

Room _room({bool isLive = true, bool closed = false, int listeners = 3, DateTime? lastActiveAt}) => Room(
  id: 'r1',
  name: 'Room',
  code: 'ABC234',
  hostId: 'host',
  hostName: 'host',
  hostEmoji: '🎧',
  hostColor: 0,
  visibility: RoomVisibility.private,
  mode: RoomMode.music,
  capacity: 25,
  isLive: isLive,
  closed: closed,
  listenerCount: listeners,
  lastActiveAt: lastActiveAt,
);

void main() {
  final now = DateTime(2026, 9, 25, 12);

  test('a room is active only while live, open, occupied and fresh', () {
    expect(_room(lastActiveAt: now).isActive(now), isTrue);
    expect(_room(isLive: false, lastActiveAt: now).isActive(now), isFalse, reason: 'everyone left');
    expect(_room(closed: true, isLive: false, lastActiveAt: now).isActive(now), isFalse, reason: 'ended');
    expect(_room(listeners: 0, lastActiveAt: now).isActive(now), isFalse);
    // The app was killed: no clean leave, but the heartbeats stopped.
    final lastBeat = now.subtract(const Duration(minutes: 10));
    expect(_room(lastActiveAt: lastBeat).isActive(now), isFalse, reason: 'stale');
  });

  test('ended flag round-trips from Firestore, and old rooms without it are open', () {
    final base = {'name': 'Room', 'code': 'ABC234', 'hostId': 'host', 'visibility': 'public', 'mode': 'music'};
    expect(Room.fromJson('r1', {...base, 'closed': true}).closed, isTrue);
    expect(Room.fromJson('r1', base).closed, isFalse);
  });
}
