import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// Raw brand values. Widgets should read colors through `context.synk`
/// (see [SynkColors]) so light/dark both work; use these only in themes.
abstract final class SynkPalette {
  // Brand — taken from the Synk logo (assets/brand/source/synk_logo.png):
  // cyan → blue → violet → magenta → coral on near-black. The logo keeps its
  // gradient; the interface uses these as solid colours (flat UI).
  static const Color brand = Color(0xFF7844F9); // violet: button fills, white labels
  static const Color brandLight = Color(0xFFA07CFF); // violet as text/icons on dark
  static const Color brandDeep = Color(0xFF5B2BD9); // violet as text/icons on light
  static const Color onBrand = Color(0xFFFFFFFF);

  // The rest of the logo's spectrum
  static const Color pink = Color(0xFFF836C5); // likes, dedications
  static const Color pinkDeep = Color(0xFFC0137F);
  static const Color cyan = Color(0xFF33CFFB);
  static const Color cyanDeep = Color(0xFF0369A1);
  static const Color coral = Color(0xFFFC9940);

  // Signals
  static const Color live = Color(0xFFE5173F);
  static const Color online = Color(0xFF3DDC97);
  static const Color danger = Color(0xFFFF4D5E);

  // Dark neutrals (the logo's navy-black)
  static const Color ink950 = Color(0xFF05050B);
  static const Color ink900 = Color(0xFF0D0D17);
  static const Color ink850 = Color(0xFF151523);
  static const Color ink800 = Color(0xFF1E1E30);
  static const Color ink600 = Color(0xFF34344A);
  static const Color ink400 = Color(0xFF8E8EA6);
  static const Color ink300 = Color(0xFFB3B3C7);
  static const Color ink50 = Color(0xFFF6F6FB);

  // Light neutrals
  static const Color paper = Color(0xFFF7F6FB);
  static const Color paperRaised = Color(0xFFFFFFFF);
  static const Color paperSunken = Color(0xFFECEAF4);
  static const Color slate700 = Color(0xFF45445A);
  static const Color slate500 = Color(0xFF66657C);

  /// Avatar / room-cover / vibe colours — the logo's spectrum, deepened so each
  /// is >= 4.5:1 against white glyphs. The index is stored on profiles and
  /// rooms, so order and length must stay stable.
  static const List<Color> identity = [
    Color(0xFF0369A1), // cyan
    Color(0xFF2F5BFF), // blue
    Color(0xFF1B1ED2), // deep blue (the logo's fold)
    Color(0xFF6D28D9), // violet
    Color(0xFFA21CAF), // magenta
    Color(0xFFBE185D), // pink
    Color(0xFFC2410C), // coral
    Color(0xFF334155), // slate
  ];

  static Color identityColor(int index) => identity[index.abs() % identity.length];

  static const List<String> avatarEmojis = ['🎧', '🎸', '🎹', '🎤', '🥁', '🎷', '🪩', '🌙', '🔥', '🌊', '🦋', '👾'];
}

abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Horizontal page gutter.
  static const double gutter = 20;
}

abstract final class Radii {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);

  /// Material 3 "emphasized" — quick start, soft landing.
  static const Curve emphasized = Cubic(0.2, 0, 0, 1);
  static const Curve standard = Curves.easeOutCubic;
}
