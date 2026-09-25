import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synk/core/design_system/design_system.dart';
import 'package:synk/features/rooms/application/huddle_controller.dart';
import 'package:synk/features/rooms/application/huddle_state.dart';
import 'package:synk/features/rooms/domain/huddle_models.dart';
import 'package:synk/features/rooms/presentation/widgets/huddle_bar.dart';

HuddleMember _m(String uid, {bool mic = true, bool cam = false}) =>
    HuddleMember(uid: uid, name: uid, emoji: '🎧', color: 1, sid: 'sid-$uid-0001', joinedAt: 0, mic: mic, cam: cam);

/// A huddle we're already in, without WebRTC or Firebase.
class _LiveHuddle extends HuddleController {
  _LiveHuddle(this.members);

  final List<HuddleMember> members;

  @override
  HuddleState build() => HuddleState(roomId: 'r1', myUid: members.first.uid, phase: HuddlePhase.live, members: members);
}

Widget _host(List<HuddleMember> members, {bool live = false, double textScale = 1}) => ProviderScope(
  overrides: [
    huddleMembersProvider.overrideWith((ref, roomId) => Stream.value(members)),
    if (live) huddleProvider.overrideWith(() => _LiveHuddle(members)),
  ],
  retry: (_, _) => null,
  child: MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, extensions: const [SynkColors.dark]),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: const Scaffold(
      body: Column(
        children: [
          HuddleHeaderButton(),
          HuddleBar(roomId: 'r1'),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('hidden while nobody is in the huddle', (tester) async {
    await tester.pumpWidget(_host(const []));
    await tester.pump();
    expect(find.text('Join'), findsNothing);
    expect(find.byTooltip('Start a huddle'), findsOneWidget);
  });

  testWidgets('shows who is talking and a Join button, even on a 360dp phone', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host([_m('maya'), _m('arjun', mic: false), _m('zoya', cam: true)]));
    await tester.pump();
    expect(find.text('Huddle'), findsOneWidget);
    expect(find.text('3 people talking'), findsOneWidget);
    expect(find.text('Join'), findsOneWidget);
    expect(tester.takeException(), isNull); // no RenderFlex overflow
  });

  testWidgets('names the one person in it', (tester) async {
    await tester.pumpWidget(_host([_m('maya')]));
    await tester.pump();
    expect(find.text('maya is talking'), findsOneWidget);
  });

  group('on a 360dp phone', () {
    setUp(() {
      final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(360, 720);
      view.devicePixelRatio = 1;
    });
    tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.reset());

    testWidgets('the join strip grows with the largest text size instead of overflowing', (tester) async {
      await tester.pumpWidget(_host([_m('maya'), _m('arjun')], textScale: 1.35));
      await tester.pump();
      expect(find.text('Join'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('in a full huddle: avatars scroll, controls stay put', (tester) async {
      final everyone = [for (var i = 0; i < 8; i++) _m('member$i', mic: i.isEven, cam: i < 4)];
      await tester.pumpWidget(_host(everyone, live: true, textScale: 1.35));
      await tester.pump();
      expect(find.byTooltip('Mute'), findsOneWidget);
      expect(find.byTooltip('Turn camera on'), findsOneWidget);
      expect(find.byTooltip('Leave huddle'), findsOneWidget);
      expect(find.byTooltip('Open huddle'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
