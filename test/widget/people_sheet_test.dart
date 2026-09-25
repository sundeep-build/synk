import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:synk/core/design_system/design_system.dart';
import 'package:synk/features/rooms/application/room_providers.dart';
import 'package:synk/features/rooms/application/room_session.dart';
import 'package:synk/features/rooms/application/room_session_controller.dart';
import 'package:synk/features/rooms/domain/room.dart';
import 'package:synk/features/rooms/domain/room_live_models.dart';
import 'package:synk/features/rooms/presentation/widgets/room_lists.dart';
import 'package:synk/features/rooms/sync/server_clock.dart';

const _now = 1000000000;

class _Clock extends Mock implements ServerClock {}

class _Session extends RoomSessionController {
  _Session(this._session);

  final RoomSession _session;

  @override
  RoomSession? build() => _session;
}

RoomMember _member(String uid, int joinedAt) =>
    RoomMember(uid: uid, name: uid, emoji: '🎧', color: 0, joinedAt: joinedAt);

RosterEntry _entry(String uid, int lastSeen) =>
    RosterEntry(uid: uid, name: uid, emoji: '🎧', color: 0, lastSeen: lastSeen);

Widget people({required List<RoomMember> here, required List<RosterEntry> roster}) {
  const room = Room(
    id: 'r1',
    name: 'Room',
    code: 'ABC123',
    hostId: 'host',
    hostName: 'host',
    hostEmoji: '🎧',
    hostColor: 0,
    visibility: RoomVisibility.private,
    mode: RoomMode.music,
    capacity: 25,
  );
  final clock = _Clock();
  when(clock.nowMs).thenReturn(_now);
  return ProviderScope(
    overrides: [
      roomSessionProvider.overrideWith(() => _Session(RoomSession(room: room, myUid: 'maya', members: here))),
      roomRosterProvider('r1').overrideWith((_) => Stream.value(roster)),
      serverClockProvider.overrideWithValue(clock),
    ],
    child: MaterialApp(
      theme: ThemeData(brightness: Brightness.dark, extensions: const [SynkColors.dark]),
      home: const Scaffold(body: RoomMembersView()),
    ),
  );
}

void main() {
  testWidgets('lists who is here, then who joined but is away, latest first', (tester) async {
    await tester.pumpWidget(
      people(
        here: [_member('maya', 1), _member('dev', 2)],
        roster: [
          _entry('maya', _now),
          _entry('dev', _now),
          _entry('host', _now - const Duration(hours: 2).inMilliseconds),
          _entry('sam', _now - const Duration(minutes: 5).inMilliseconds),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('In the room · 2'), findsOneWidget);
    expect(find.text('maya (you)'), findsOneWidget);
    expect(find.text('Away · 2'), findsOneWidget);
    expect(find.text('Last seen 5m ago'), findsOneWidget);
    // The host is away: they keep their badge, and the earliest here acts for them.
    expect(find.text('HOST'), findsOneWidget);
    expect(find.text('ACTING HOST'), findsOneWidget);
    final sam = tester.getTopLeft(find.text('sam')).dy;
    expect(sam, lessThan(tester.getTopLeft(find.text('host')).dy));
    expect(sam, greaterThan(tester.getTopLeft(find.text('dev')).dy));
  });

  testWidgets('no Away section when everyone is here', (tester) async {
    await tester.pumpWidget(people(here: [_member('maya', 1)], roster: [_entry('maya', _now)]));
    await tester.pump();
    expect(find.text('In the room · 1'), findsOneWidget);
    expect(find.textContaining('Away'), findsNothing);
  });

  test('roster entries without a name are dropped', () {
    expect(RosterEntry.fromJson('u', {'lastSeen': 5}), isNull);
    expect(RosterEntry.fromJson('u', {'name': 'maya', 'lastSeen': 5})?.lastSeen, 5);
  });
}
