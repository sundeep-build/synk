import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synk/core/design_system/design_system.dart';
import 'package:synk/features/auth/presentation/welcome_screen.dart';
import 'package:synk/features/rooms/application/room_providers.dart';
import 'package:synk/features/rooms/domain/room.dart';
import 'package:synk/features/rooms/domain/room_live_models.dart';
import 'package:synk/features/rooms/presentation/widgets/room_card.dart';

/// Test theme without GoogleFonts (no network in tests).
Widget _host(Widget child) => MaterialApp(
  theme: ThemeData(brightness: Brightness.dark, extensions: const [SynkColors.dark]),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('PrimaryButton fires and exposes button semantics', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(PrimaryButton(label: 'Go live', onPressed: () => taps++)));
    await tester.tap(find.text('Go live'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(
      tester.getSemantics(find.byType(PrimaryButton)),
      matchesSemantics(label: 'Go live', isButton: true, isEnabled: true, hasEnabledState: true, hasTapAction: true),
    );
  });

  testWidgets('PrimaryButton is inert while loading', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(PrimaryButton(label: 'Save', loading: true, onPressed: () => taps++)));
    await tester.tap(find.byType(PrimaryButton));
    await tester.pump();
    expect(taps, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('LiveBadge announces listener count', (tester) async {
    await tester.pumpWidget(_host(const LiveBadge(count: 12)));
    expect(find.text('LIVE · 12'), findsOneWidget);
    expect(find.bySemanticsLabel('Live, 12 listening'), findsOneWidget);
  });

  testWidgets('AvatarStack shows overflow count', (tester) async {
    await tester.pumpWidget(
      _host(
        const AvatarStack(
          avatars: [(emoji: '🎧', colorIndex: 0), (emoji: '🎸', colorIndex: 1), (emoji: '🎹', colorIndex: 2)],
          total: 10,
          max: 2,
        ),
      ),
    );
    expect(find.text('+8'), findsOneWidget);
  });

  testWidgets('EqualizerBars stops animating when inactive', (tester) async {
    await tester.pumpWidget(_host(const EqualizerBars(active: false)));
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(_host(const EqualizerBars()));
    expect(tester.hasRunningAnimations, isTrue);
  });

  // Chat pane / queue with the keyboard up: the exact 360×158 slot from the
  // reported overflow (EmptyState's Column got only 94px after its padding).
  testWidgets('EmptyState fits a keyboard-squeezed pane without overflowing', (tester) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 360,
          height: 158.3,
          child: EmptyState(
            icon: Icons.waving_hand_rounded,
            title: 'Say hi',
            message: 'Chat, react, dedicate a song.',
            action: OutlinedButton(onPressed: () {}, child: const Text('Try again')),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Say hi'), findsOneWidget);
  });

  testWidgets('EmptyState keeps its icon when there is room', (tester) async {
    await tester.pumpWidget(
      _host(const EmptyState(icon: Icons.queue_music_rounded, title: 'Queue is empty', message: 'Add songs.')),
    );
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.queue_music_rounded), findsOneWidget);
  });

  testWidgets('RoomTile shows who is in the room and fits a 360dp phone at large text', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const room = Room(
      id: 'r1',
      name: 'Late night Punjabi drives with the whole crew',
      code: 'ABC123',
      hostId: 'h',
      hostName: 'sandeep_the_host',
      hostEmoji: '🎧',
      hostColor: 1,
      visibility: RoomVisibility.public,
      mode: RoomMode.music,
      capacity: 25,
      listenerCount: 12,
      nowPlaying: NowPlayingSummary(title: 'A very long song title that goes on', artist: 'Some Artist'),
    );
    final members = [
      for (var i = 0; i < 4; i++) RoomMember(uid: 'u$i', name: 'u$i', emoji: '🔥', color: i, joinedAt: i),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [roomListenersPreviewProvider('r1').overrideWith((_) async => members)],
        child: MediaQuery(
          data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(1.35)),
          child: _host(
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: RoomTile(room: room),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('+8'), findsOneWidget, reason: '4 avatars shown of 12 listening');
  });

  testWidgets('RoomCard (flat) fits the Home carousel at the largest text size', (tester) async {
    const room = Room(
      id: 'r2',
      name: 'Late night Punjabi drives with the whole crew',
      code: 'ABC123',
      hostId: 'h',
      hostName: 'sandeep_the_host',
      hostEmoji: '🎧',
      hostColor: 1,
      visibility: RoomVisibility.public,
      mode: RoomMode.radio,
      capacity: 25,
      listenerCount: 7,
      nowPlaying: NowPlayingSummary(title: 'A very long song title that goes on', artist: 'Some Artist'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [roomListenersPreviewProvider('r2').overrideWith((_) async => const [])],
        child: MediaQuery(
          data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(1.35)),
          child: _host(const RoomCard(room: room)),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('@sandeep_the_host'), findsOneWidget);
  });

  testWidgets('AppLogo shows the bundled Synk mark', (tester) async {
    await tester.pumpWidget(_host(const AppLogo(size: 72)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Synk logo'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as ResizeImage).imageProvider, isA<AssetImage>());
  });
}
