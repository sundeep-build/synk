import 'package:flutter_test/flutter_test.dart';
import 'package:synk/features/rooms/domain/remembered_rooms.dart';

void main() {
  test('joining lists the room first, once, and marks it to reopen', () {
    final r = const RememberedRooms(uid: 'u1').join('a').join('b').join('a');
    expect(r.joined, ['a', 'b']);
    expect(r.active, 'a');
  });

  test('keeps at most ${RememberedRooms.max} rooms, dropping the oldest', () {
    var r = const RememberedRooms(uid: 'u1');
    for (var i = 0; i < RememberedRooms.max + 3; i++) {
      r = r.join('r$i');
    }
    expect(r.joined.length, RememberedRooms.max);
    expect(r.joined.first, 'r${RememberedRooms.max + 2}');
    expect(r.joined, isNot(contains('r0')));
  });

  test('leaving on purpose keeps it listed but not reopened', () {
    final r = const RememberedRooms(uid: 'u1').join('a').leave();
    expect(r.joined, ['a']);
    expect(r.active, isNull);
  });

  test('forgetting removes it, and stops reopening only that room', () {
    final r = const RememberedRooms(uid: 'u1').join('a').join('b');
    expect(r.forget('a').joined, ['b']);
    expect(r.forget('a').active, 'b');
    expect(r.forget('b').active, isNull);
  });

  test('round-trips, and another user on the device reads as none', () {
    final r = const RememberedRooms(uid: 'u1').join('a').join('b');
    final back = RememberedRooms.fromJson(r.toJson(), 'u1');
    expect(back.joined, ['b', 'a']);
    expect(back.active, 'b');
    expect(RememberedRooms.fromJson(r.toJson(), 'u2').joined, isEmpty);
    expect(RememberedRooms.fromJson(null, 'u1').active, isNull);
    expect(RememberedRooms.fromJson({'uid': 'u1', 'joined': 'oops', 'active': 3}, 'u1').joined, isEmpty);
  });
}
