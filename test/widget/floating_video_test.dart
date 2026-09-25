import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synk/core/design_system/design_system.dart';
import 'package:synk/features/auth/application/session.dart';
import 'package:synk/features/catalog/domain/track.dart';
import 'package:synk/features/player/application/player_providers.dart';
import 'package:synk/features/player/presentation/floating_video.dart';
import 'package:synk/features/player/presentation/video_slot.dart';
import 'package:synk/features/profile/domain/user_profile.dart';

const _video = Track(
  id: 'yt:abcdefghijk',
  source: TrackSource.youtube,
  title: 'Late night drive',
  artist: 'Artist',
  streamUrl: '',
  durationMs: 200000,
);

/// Records play/pause instead of driving a real player.
class _FakeSolo extends SoloPlayerController {
  final calls = <String>[];

  @override
  SoloQueue build() => const SoloQueue();

  @override
  Future<void> onPause() async => calls.add('pause');

  @override
  Future<void> onPlay() async => calls.add('play');
}

class _FakePlayer extends StatefulWidget {
  const _FakePlayer({super.key});

  static int created = 0;

  @override
  State<_FakePlayer> createState() => _FakePlayerState();
}

class _FakePlayerState extends State<_FakePlayer> {
  @override
  void initState() {
    super.initState();
    _FakePlayer.created++;
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}

void main() {
  late _FakeSolo solo;

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _FakePlayer.created = 0;
    solo = _FakeSolo();
    final registry = VideoStageRegistry()..playerBuilder = (key, _) => _FakePlayer(key: key);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          videoStageRegistryProvider.overrideWithValue(registry),
          videoFloatEligibleProvider.overrideWith((ref) => Stream.value(true)),
          currentTrackProvider.overrideWith((ref) => Stream.value(_video)),
          isPlayingProvider.overrideWithValue(true),
          soloPlayerProvider.overrideWith(() => solo),
          currentProfileProvider.overrideWithValue(
            const UserProfile(uid: 'me', username: 'me', displayName: 'Me', avatarEmoji: 'c:1', avatarColor: 2),
          ),
        ],
        retry: (_, _) => null,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, extensions: const [SynkColors.dark]),
          // No dancing in tests: it animates forever.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Stack(
              children: [
                child!,
                const Positioned.fill(child: FloatingVideo()),
              ],
            ),
          ),
          home: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder tucked() => find.bySemanticsLabel('Video tucked away. Show it again');

  testWidgets('drag it off an edge to tuck it; tap the avatar to bring it back', (tester) async {
    await pumpApp(tester);
    expect(find.text('Late night drive'), findsOneWidget);
    expect(find.byType(DancingAvatar), findsOneWidget, reason: 'your avatar rides in the title bar');

    await tester.drag(find.text('Late night drive'), const Offset(-360, 0));
    await tester.pumpAndSettle();
    expect(tucked(), findsOneWidget);
    expect(find.text('Late night drive'), findsNothing, reason: 'the video is tucked away…');
    expect(solo.calls, ['pause'], reason: '…and paused: YouTube never plays unseen');
    expect(tester.getTopLeft(tucked()).dx, lessThan(20), reason: 'waits on the edge it went to');

    await tester.tap(tucked());
    await tester.pumpAndSettle();
    expect(find.text('Late night drive'), findsOneWidget);
    expect(solo.calls, ['pause', 'play']);

    // A quick throw to the right tucks it on that side.
    await tester.fling(find.text('Late night drive'), const Offset(220, 0), 2500);
    await tester.pumpAndSettle();
    expect(tester.getTopRight(tucked()).dx, greaterThan(380));

    expect(_FakePlayer.created, 1, reason: 'tucking never reloads the video');
  });

  testWidgets('let go anywhere: it springs to the nearer side, never mid-screen', (tester) async {
    await pumpApp(tester);
    await tester.drag(find.text('Late night drive'), const Offset(-150, -200));
    await tester.pumpAndSettle();
    expect(tucked(), findsNothing);
    final card = tester.getTopLeft(find.text('Late night drive'));
    expect(card.dx, lessThan(60), reason: 'snapped to the left side');
  });
}
