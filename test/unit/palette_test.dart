import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synk/core/design_system/design_system.dart';

double _contrast(Color a, Color b) {
  final (hi, lo) = a.computeLuminance() > b.computeLuminance() ? (a, b) : (b, a);
  return (hi.computeLuminance() + 0.05) / (lo.computeLuminance() + 0.05);
}

void main() {
  test('labels on the solid brand colour pass WCAG AA', () {
    expect(_contrast(SynkPalette.onBrand, SynkPalette.brand), greaterThanOrEqualTo(4.5));
  });

  test('primary as text/icons reads on both themes', () {
    for (final (b, c) in [(Brightness.dark, SynkColors.dark), (Brightness.light, SynkColors.light)]) {
      final primary = AppTheme.scheme(b).primary;
      expect(_contrast(primary, c.background), greaterThanOrEqualTo(4.5), reason: '$b');
      expect(_contrast(primary, c.surfaceRaised), greaterThanOrEqualTo(4.5), reason: '$b');
    }
  });

  test('brand fills (buttons, rings, borders) stand out as shapes on both themes', () {
    expect(_contrast(SynkPalette.brand, SynkColors.dark.background), greaterThanOrEqualTo(3));
    expect(_contrast(SynkPalette.brand, SynkColors.light.background), greaterThanOrEqualTo(3));
  });

  test('white glyphs read on every identity colour (avatars, covers, vibes)', () {
    for (final c in SynkPalette.identity) {
      expect(_contrast(Colors.white, c), greaterThanOrEqualTo(4.5), reason: '$c');
    }
  });

  test('chat names in identity colours read on both themes', () {
    for (var i = 0; i < SynkPalette.identity.length; i++) {
      expect(_contrast(SynkColors.dark.identityText(i), SynkColors.dark.surfaceRaised), greaterThanOrEqualTo(4.5));
      expect(_contrast(SynkColors.light.identityText(i), SynkColors.light.surfaceRaised), greaterThanOrEqualTo(4.5));
    }
  });

  test('body and muted text pass AA on both themes', () {
    for (final t in [SynkColors.dark, SynkColors.light]) {
      for (final fg in [t.textPrimary, t.textSecondary, t.textMuted]) {
        expect(_contrast(fg, t.background), greaterThanOrEqualTo(4.5));
        expect(_contrast(fg, t.surfaceRaised), greaterThanOrEqualTo(4.5));
      }
    }
  });
}
