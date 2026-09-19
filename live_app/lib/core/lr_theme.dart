import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Live Ride design tokens.
///
/// The product is an instrument first and an app second: white panels, hairline
/// separators, black type, one cyan accent and a red alert colour. No elevation
/// games, no gradients, no oversized rounded cards.
abstract final class LR {
  static const Color ink = Color(0xFF0B1116);
  static const Color inkSoft = Color(0xFF47555F);
  static const Color muted = Color(0xFF7C8A95);
  static const Color line = Color(0xFFD7DEE4);
  static const Color lineStrong = Color(0xFFB4C0C9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color canvas = Color(0xFFEFF2F5);
  static const Color panel = Color(0xFFF7F9FB);

  static const Color accent = Color(0xFF00BFD8);
  static const Color accentDeep = Color(0xFF0090A8);
  static const Color alert = Color(0xFFE02B20);
  static const Color go = Color(0xFF00A868);

  static const Color night = Color(0xFF07101A);
  static const Color nightPanel = Color(0xFF0E1A24);
  static const Color nightLine = Color(0xFF1D2C38);

  /// Tabular figures everywhere a number can change while being read.
  static const List<FontFeature> numeric = [
    FontFeature.tabularFigures(),
    FontFeature.slashedZero(),
  ];

  static const TextStyle fieldLabel = TextStyle(
    fontSize: 11,
    height: 1.0,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.1,
    color: inkSoft,
  );

  static const TextStyle fieldUnit = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: inkSoft,
  );

  static TextStyle fieldValue(double size) => TextStyle(
    fontSize: size,
    height: 0.92,
    fontWeight: FontWeight.w800,
    letterSpacing: -size * 0.035,
    color: ink,
    fontFeatures: numeric,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w900,
    letterSpacing: 1.4,
    color: inkSoft,
  );

  static const TextStyle title = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    color: ink,
  );

  static const TextStyle body = TextStyle(fontSize: 14, color: inkSoft);

  static const SystemUiOverlayStyle lightStatusBar = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );

  static ThemeData theme() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: accent,
      onPrimary: ink,
      secondary: accentDeep,
      onSecondary: Colors.white,
      error: alert,
      onError: Colors.white,
      surface: surface,
      onSurface: ink,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: lightStatusBar,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.2,
        ),
      ),
      textTheme: const TextTheme(
        titleLarge: title,
        bodyMedium: TextStyle(color: ink, fontSize: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 14,
            letterSpacing: 0.8,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: lineStrong),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
          minimumSize: const Size.fromHeight(48),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            letterSpacing: 0.4,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentDeep,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          borderSide: BorderSide(color: accentDeep, width: 1.6),
        ),
        labelStyle: TextStyle(color: inkSoft, fontWeight: FontWeight.w600),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? ink : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : const Color(0xFFDCE3E8),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: TextStyle(color: Colors.white, fontSize: 13.5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
        contentTextStyle: TextStyle(color: inkSoft, fontSize: 14),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: inkSoft,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        subtitleTextStyle: TextStyle(color: muted, fontSize: 12.5),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accentDeep,
        linearTrackColor: line,
      ),
    );
  }
}
