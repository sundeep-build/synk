import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synk/core/design_system/design_system.dart';

void main() {
  test('avatar values: c:<n> is a character, anything else stays an emoji', () {
    expect(CartoonAvatar.indexOf(CartoonAvatar.code(3)), 3);
    expect(CartoonAvatar.indexOf('c:11'), 11);
    expect(CartoonAvatar.indexOf('c:12'), isNull, reason: 'out of range');
    expect(CartoonAvatar.indexOf('c:x'), isNull);
    expect(CartoonAvatar.indexOf('🎧'), isNull);
    // Stored in fields the rules cap at 8 characters.
    for (var i = 0; i < CartoonAvatar.count; i++) {
      expect(CartoonAvatar.code(i).length, lessThanOrEqualTo(8));
    }
  });

  testWidgets('every character paints at list and profile sizes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, extensions: const [SynkColors.dark]),
        home: Scaffold(
          body: Wrap(
            children: [
              for (var i = 0; i < CartoonAvatar.count; i++) ...[
                SynkAvatar(emoji: CartoonAvatar.code(i), colorIndex: i, size: 30),
                SynkAvatar(emoji: CartoonAvatar.code(i), colorIndex: i, size: 112, ring: true),
              ],
              const SynkAvatar(emoji: '🎷', colorIndex: 2),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(CartoonAvatar), findsNWidgets(CartoonAvatar.count * 2));
    expect(find.bySemanticsLabel('Jazz Fox'), findsNWidgets(2));
    expect(find.text('🎷'), findsOneWidget, reason: 'emoji avatars still work');
  });
}
