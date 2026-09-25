import 'package:flutter/material.dart';

import 'tokens.dart';

/// Semantic colors not covered by [ColorScheme]. Access with `context.synk`.
@immutable
class SynkColors extends ThemeExtension<SynkColors> {
  const SynkColors({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceOverlay,
    required this.glassFill,
    required this.glassBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.live,
    required this.online,
    required this.skeleton,
    required this.brand,
    required this.onBrand,
    required this.accent,
    required this.identityTint,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceOverlay;
  final Color glassFill;
  final Color glassBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color live;
  final Color online;
  final Color skeleton;

  /// The one solid brand fill: primary buttons, Go live, the logo, rings.
  final Color brand;

  /// Text/icons drawn on [brand] (white on the logo's violet).
  final Color onBrand;

  /// Secondary pop (likes, dedications, highlights) — hot pink.
  final Color accent;

  /// How far identity colours are lightened when used as *text* (chat names):
  /// they're dark enough for white glyphs, too dark to read on charcoal.
  final double identityTint;

  /// A person's identity colour, readable as text on this theme's surfaces.
  Color identityText(int index) => Color.lerp(SynkPalette.identityColor(index), Colors.white, identityTint)!;

  static const dark = SynkColors(
    background: SynkPalette.ink950,
    surface: SynkPalette.ink900,
    surfaceRaised: SynkPalette.ink850,
    surfaceOverlay: SynkPalette.ink800,
    glassFill: Color(0xE6111331), // 90% ink900
    glassBorder: Color(0x1FFFFFFF), // 12% white
    textPrimary: SynkPalette.ink50,
    textSecondary: SynkPalette.ink300,
    textMuted: SynkPalette.ink400,
    live: SynkPalette.live,
    online: SynkPalette.online,
    skeleton: SynkPalette.ink850,
    brand: SynkPalette.brand,
    onBrand: SynkPalette.onBrand,
    accent: SynkPalette.pink,
    identityTint: 0.45,
  );

  static const light = SynkColors(
    background: SynkPalette.paper,
    surface: SynkPalette.paperRaised,
    surfaceRaised: SynkPalette.paperRaised,
    surfaceOverlay: SynkPalette.paperSunken,
    glassFill: Color(0xD9FFFFFF),
    glassBorder: Color(0x14000000),
    textPrimary: SynkPalette.ink950,
    textSecondary: SynkPalette.slate700,
    textMuted: SynkPalette.slate500,
    live: Color(0xFFD0103A),
    online: Color(0xFF00845A),
    skeleton: SynkPalette.paperSunken,
    brand: SynkPalette.brand,
    onBrand: SynkPalette.onBrand,
    accent: SynkPalette.pinkDeep,
    identityTint: 0,
  );

  @override
  SynkColors copyWith() => this;

  @override
  SynkColors lerp(ThemeExtension<SynkColors>? other, double t) {
    if (other is! SynkColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return SynkColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      surfaceOverlay: l(surfaceOverlay, other.surfaceOverlay),
      glassFill: l(glassFill, other.glassFill),
      glassBorder: l(glassBorder, other.glassBorder),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textMuted: l(textMuted, other.textMuted),
      live: l(live, other.live),
      online: l(online, other.online),
      skeleton: l(skeleton, other.skeleton),
      brand: l(brand, other.brand),
      onBrand: l(onBrand, other.onBrand),
      accent: l(accent, other.accent),
      identityTint: identityTint + (other.identityTint - identityTint) * t,
    );
  }
}

extension SynkThemeX on BuildContext {
  SynkColors get synk => Theme.of(this).extension<SynkColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
  ColorScheme get colors => Theme.of(this).colorScheme;
}
