import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'synk_colors.dart';
import 'synk_type.dart';
import 'tokens.dart';

/// Builds light/dark [ThemeData] from the tokens.
///
/// Typography: Montserrat throughout — geometric and bold for headings
/// (section titles pair a heavy first word with a light second one, see
/// SectionHeader), and still very legible at small sizes. Fetched once and
/// cached; bundle it under `assets/google_fonts/` for a fully offline first
/// launch.
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
      extensions: [
        c,
        // Every weight the UI switches between, registered (and fetched) up front.
        SynkType({
          for (final w in const [FontWeight.w400, FontWeight.w500, FontWeight.w600, FontWeight.w700, FontWeight.w800])
            w: GoogleFonts.montserrat(fontWeight: w).fontFamily!,
        }),
      ],
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
        // Clear over the page, solid once content scrolls beneath (pinned
        // bars would otherwise show the list through the title).
        backgroundColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.scrolledUnder) ? c.background : Colors.transparent,
        ),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      // Outlined pill fields.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        hintStyle: text.bodyMedium?.copyWith(color: c.textMuted),
        prefixIconColor: c.textSecondary,
        suffixIconColor: c.textSecondary,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.lg),
        border: const OutlineInputBorder(borderRadius: Radii.xlAll, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.xlAll,
          borderSide: BorderSide(color: c.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.xlAll,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: Radii.xlAll,
          borderSide: BorderSide(color: SynkPalette.danger),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: Radii.xlAll,
          borderSide: BorderSide(color: SynkPalette.danger, width: 1.5),
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
      // Soft-cornered tags; the selected one turns solid pink.
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(borderRadius: Radii.smAll),
        side: BorderSide(color: c.glassBorder),
        backgroundColor: c.surfaceRaised,
        selectedColor: SynkPalette.pinkDeep,
        labelStyle: text.labelMedium?.copyWith(color: c.textPrimary),
        secondaryLabelStyle: text.labelMedium?.copyWith(color: Colors.white),
        iconTheme: IconThemeData(color: c.textSecondary, size: 16),
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
        activeTrackColor: scheme.tertiary,
        inactiveTrackColor: c.glassBorder,
        thumbColor: c.textPrimary,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: c.onBrand,
        unselectedLabelColor: c.textSecondary,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge,
        indicator: BoxDecoration(color: c.brand, borderRadius: Radii.pillAll),
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
    TextStyle display(double size, FontWeight weight, double tracking) => GoogleFonts.montserrat(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: tracking,
      height: 1.12,
      color: c.textPrimary,
    );
    TextStyle body(double size, FontWeight weight, {double height = 1.4, Color? color}) =>
        GoogleFonts.montserrat(fontSize: size, fontWeight: weight, height: height, color: color ?? c.textPrimary);

    return TextTheme(
      displayLarge: display(44, FontWeight.w800, -1.2),
      displayMedium: display(38, FontWeight.w800, -1),
      displaySmall: display(30, FontWeight.w800, -0.6),
      headlineLarge: display(26, FontWeight.w800, -0.4),
      headlineMedium: display(22, FontWeight.w700, -0.3),
      headlineSmall: display(19, FontWeight.w700, -0.2),
      titleLarge: display(18, FontWeight.w700, -0.2),
      titleMedium: body(14, FontWeight.w600, height: 1.3),
      titleSmall: body(13, FontWeight.w600, height: 1.3),
      bodyLarge: body(15, FontWeight.w500),
      bodyMedium: body(13, FontWeight.w500),
      bodySmall: body(11.5, FontWeight.w500, color: c.textSecondary),
      labelLarge: body(14, FontWeight.w600, height: 1.2),
      labelMedium: body(12, FontWeight.w600, height: 1.2),
      labelSmall: body(10.5, FontWeight.w600, height: 1.2),
    );
  }
}
