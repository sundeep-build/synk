import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synk/features/player/presentation/video_slot.dart';
import 'package:synk/features/player/presentation/youtube_stage.dart';

/// Stands in for the YouTube player (a real one needs a WebView) and counts
/// how often it's built from scratch: every rebuild would be a video reload.
class _FakePlayer extends StatefulWidget {
  const _FakePlayer({required this.where, super.key});

  final String where;

  static int created = 0;
  static int disposed = 0;

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
  void dispose() {
    _FakePlayer.disposed++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('player in ${widget.where}');
}

void main() {
  testWidgets('one player moves room → floating → PiP → back without ever being rebuilt', (tester) async {
    _FakePlayer.created = 0;
    _FakePlayer.disposed = 0;
    final registry = VideoStageRegistry()
      ..playerBuilder = (key, c) => _FakePlayer(
        key: key,
        where: c.fill
            ? 'pip'
            : c.floating
            ? 'floating'
            : 'room',
      );
    final navigator = GlobalKey<NavigatorState>();
    final floatingClaim = ValueNotifier(true); // a video is playing
    final pipClaim = ValueNotifier(false);
    var inPip = false;
    late StateSetter setApp;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [videoStageRegistryProvider.overrideWithValue(registry)],
        child: MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('home')),
          builder: (context, child) => StatefulBuilder(
            builder: (context, setState) {
              setApp = setState;
              return Stack(
                children: [
                  child!,
                  Positioned(
                    left: 0,
                    bottom: 0,
                    width: 220,
                    height: 60,
                    child: VideoSlot(
                      priority: VideoSlot.floating,
                      claim: floatingClaim,
                      stage: const YouTubeStage(floating: true),
                      builder: (_, player) => player ?? const SizedBox.shrink(),
                    ),
                  ),
                  if (inPip)
                    Positioned.fill(
                      child: VideoSlot(
                        priority: VideoSlot.pip,
                        claim: pipClaim,
                        stage: const YouTubeStage(fill: true, floating: true),
                        builder: (_, player) => player ?? const SizedBox.shrink(),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    // A slot that mounts claims mid-build, so it gets the player one frame later.
    await tester.pump();
    expect(find.text('player in floating'), findsOneWidget);

    // Open the room: it takes the playing video.
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: VideoSlot(stage: YouTubeStage())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('player in room'), findsOneWidget);
    expect(find.text('player in floating'), findsNothing);

    // Minimise: the floating card has it on the very next frame, while the
    // room is still animating out.
    navigator.currentState!.pop();
    await tester.pump();
    expect(find.text('player in floating'), findsOneWidget);
    expect(find.text('player in room'), findsNothing);
    await tester.pumpAndSettle();

    // Into PiP and back out.
    pipClaim.value = true;
    setApp(() => inPip = true);
    await tester.pump(); // the PiP slot mounts…
    await tester.pump(); // …and has the player
    expect(find.text('player in pip'), findsOneWidget);
    pipClaim.value = false;
    setApp(() => inPip = false);
    await tester.pump();
    expect(find.text('player in floating'), findsOneWidget);

    expect(_FakePlayer.created, 1, reason: 'built once: never reloaded along the way');
    expect(_FakePlayer.disposed, 0);

    // ✕ on the floating card: now it goes.
    floatingClaim.value = false;
    await tester.pump();
    expect(find.textContaining('player in'), findsNothing);
    expect(_FakePlayer.disposed, 1);
  });
}
