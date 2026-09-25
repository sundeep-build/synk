import 'package:flutter/material.dart';

/// Changes a text style's weight *correctly*.
///
/// google_fonts registers every weight of a font as its own family
/// (`Montserrat_700`, …), so `copyWith(fontWeight: …)` alone keeps drawing
/// the old weight's letterforms: a "light" word stays bold. This maps each
/// weight to its registered family. The families are loaded by AppTheme,
/// so switching is instant.
@immutable
class SynkType extends ThemeExtension<SynkType> {
  const SynkType(this._families);

  final Map<FontWeight, String> _families;

  TextStyle weight(TextStyle base, FontWeight weight) =>
      base.copyWith(fontWeight: weight, fontFamily: _families[weight] ?? base.fontFamily);

  @override
  SynkType copyWith() => this;

  @override
  SynkType lerp(ThemeExtension<SynkType>? other, double t) => t < 0.5 ? this : (other as SynkType? ?? this);
}

extension SynkTypeX on BuildContext {
  /// [base] at [weight] (see [SynkType]). Without the extension (plain test
  /// themes) it's a plain `copyWith`.
  TextStyle weight(TextStyle? base, FontWeight weight) {
    final style = base ?? DefaultTextStyle.of(this).style;
    return Theme.of(this).extension<SynkType>()?.weight(style, weight) ?? style.copyWith(fontWeight: weight);
  }
}
