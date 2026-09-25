import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'synk_colors.dart';
import 'tokens.dart';

/// Builds light/dark [ThemeData] from the tokens.
///
/// Typography: Bricolage Grotesque (display — characterful, music-poster
/// energy) over Plus Jakarta Sans (body — clean and very legible at small
/// sizes). Fonts are fetched once and cached; bundle them under
/// `assets/google_fonts/` for fully offline first launch.
abstract final class AppTheme {
  static ThemeData dark() => _build(Brightness.dark, SynkColors.dark);
  static ThemeData light() => _build(Brightness.light, SynkColors.light);

  /// The colour scheme alone (no fonts), e.g. for contrast tests.
  static ColorScheme scheme(Brightness brightness) =>
      _scheme(brightness, brightness == Brightness.dark ? SynkColors.dark : SynkColors.light);

  static ColorScheme _scheme(Brightness brightness, SynkColors c) {
    final isDark = brightness == Brightness.dark;
    return ColorScheme(
      brightness: brightness,
      primary: isDark ? SynkPalette.brandLight : SynkPalette.brandDeep,
      onPrimary: isDark ? SynkPalette.ink950 : Colors.white,
      primaryContainer: isDark ? const Color(0xFF26164F) : const Color(0xFFECE4FF),
      onPrimaryContainer: isDark ? const Color(0xFFE6DDFF) : const Color(0xFF3B1A8A),
      secondary: c.accent,
      onSecondary: isDark ? SynkPalette.ink950 : Colors.white,
      tertiary: isDark ? SynkPalette.cyan : SynkPalette.cyanDeep,
      onTertiary: isDark ? SynkPalette.ink950 : Colors.white,
      error: SynkPalette.danger,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surfaceRaised,
      surfaceContainerHigh: c.surfaceOverlay,
      surfaceContainerHighest: c.surfaceOverlay,
      outline: c.glassBorder,
      outlineVariant: c.glassBorder,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: c.textPrimary,
      onInverseSurface: c.background,
      inversePrimary: isDark ? SynkPalette.brandDeep : SynkPalette.brandLight,
    );
  }

  static ThemeData _build(Brightness brightness, SynkColors c) {
    final isDark = brightness == Brightness.dark;
    final scheme = _scheme(brightness, c);

    final text = _textTheme(c);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      textTheme: text,
      extensions: [c],
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceRaised,
        hintStyle: text.bodyLarge?.copyWith(color: c.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.lg),
        border: const OutlineInputBorder(borderRadius: Radii.mdAll, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.mdAll,
          borderSide: BorderSide(color: c.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.mdAll,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: Radii.mdAll,
          borderSide: BorderSide(color: SynkPalette.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: const StadiumBorder(),
          side: BorderSide(color: c.glassBorder),
          foregroundColor: c.textPrimary,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: text.labelLarge, shape: const StadiumBorder()),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: c.glassBorder),
        backgroundColor: c.surfaceRaised,
        selectedColor: scheme.primaryContainer,
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        showCheckmark: false,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.textMuted,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Radii.lgAll),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surfaceOverlay,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.textPrimary),
        shape: const RoundedRectangleBorder(borderRadius: Radii.mdAll),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: c.textPrimary,
        inactiveTrackColor: c.glassBorder,
        thumbColor: c.textPrimary,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: isDark ? SynkPalette.ink950 : Colors.white,
        unselectedLabelColor: c.textSecondary,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge,
        indicator: BoxDecoration(color: isDark ? SynkPalette.ink50 : SynkPalette.ink950, borderRadius: Radii.pillAll),
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      dividerTheme: DividerThemeData(color: c.glassBorder, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodySmall?.copyWith(color: c.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }

  static TextTheme _textTheme(SynkColors c) {
    TextStyle display(double size, FontWeight weight, double tracking) => GoogleFonts.bricolageGrotesque(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: tracking,
      height: 1.1,
      color: c.textPrimary,
    );
    TextStyle body(double size, FontWeight weight, {double height = 1.4, Color? color}) =>
        GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: weight, height: height, color: color ?? c.textPrimary);

    return TextTheme(
      displayLarge: display(48, FontWeight.w800, -1.6),
      displayMedium: display(40, FontWeight.w800, -1.2),
      displaySmall: display(32, FontWeight.w700, -0.8),
      headlineLarge: display(28, FontWeight.w700, -0.6),
      headlineMedium: display(24, FontWeight.w700, -0.4),
      headlineSmall: display(20, FontWeight.w700, -0.2),
      titleLarge: display(20, FontWeight.w700, -0.2),
      titleMedium: body(15, FontWeight.w700, height: 1.3),
      titleSmall: body(13, FontWeight.w700, height: 1.3),
      bodyLarge: body(16, FontWeight.w500),
      bodyMedium: body(14, FontWeight.w500),
      bodySmall: body(12, FontWeight.w500, color: c.textSecondary),
      labelLarge: body(15, FontWeight.w700, height: 1.2),
      labelMedium: body(13, FontWeight.w600, height: 1.2),
      labelSmall: body(11, FontWeight.w700, height: 1.2),
    );
  }
}
