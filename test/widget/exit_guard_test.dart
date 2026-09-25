import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synk/app/shell/exit_guard.dart';
import 'package:synk/core/design_system/design_system.dart';
import 'package:synk/features/player/application/player_providers.dart';

Widget _app({bool Function()? onBack, bool playing = false}) => ProviderScope(
  overrides: [isPlayingProvider.overrideWithValue(playing)],
  retry: (_, _) => null,
  child: MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, extensions: const [SynkColors.dark]),
    home: ExitGuard(
      onBack: onBack,
      child: const Scaffold(body: Text('home')),
    ),
  ),
);

/// Simulates Android's back button.
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  late List<MethodCall> platformCalls;

  setUp(() {
    platformCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
  });

  bool closedApp() => platformCalls.any((c) => c.method == 'SystemNavigator.pop');

  testWidgets('back asks before closing; Cancel stays in the app', (tester) async {
    await tester.pumpWidget(_app());
    await _back(tester);
    expect(find.text('Exit Synk?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Exit Synk?'), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(closedApp(), isFalse);
  });

  testWidgets('Exit closes the app and mentions music that will stop', (tester) async {
    await tester.pumpWidget(_app(playing: true));
    await _back(tester);
    expect(find.text('Music will stop playing.'), findsOneWidget);

    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();
    expect(closedApp(), isTrue);
  });

  testWidgets('onBack can handle the press (e.g. jump to the Home tab)', (tester) async {
    var handled = 0;
    await tester.pumpWidget(
      _app(
        onBack: () {
          handled++;
          return true;
        },
      ),
    );
    await _back(tester);
    expect(handled, 1);
    expect(find.text('Exit Synk?'), findsNothing);
  });
}
