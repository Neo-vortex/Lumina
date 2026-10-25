import 'package:flutter/material.dart';

import 'glow_colors.dart';

ThemeData buildGlowTheme() {
  const scheme = ColorScheme.dark(
    surface: GlowColors.surface,
    primary: GlowColors.violet,
    secondary: GlowColors.cyan,
    tertiary: GlowColors.amber,
    error: GlowColors.error,
    onSurface: GlowColors.text,
    onPrimary: Colors.white,
    outline: GlowColors.outlineStrong,
    outlineVariant: GlowColors.outline,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: GlowColors.background,
    textTheme: base.textTheme.apply(bodyColor: GlowColors.text, displayColor: GlowColors.text),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: GlowColors.cyan,
        minimumSize: const Size(48, 48), // UX-06
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: GlowColors.surfaceHigh,
      contentTextStyle: TextStyle(color: GlowColors.text),
      behavior: SnackBarBehavior.floating,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: GlowColors.cyan,
      selectionColor: Color(0x554FE3DC),
      selectionHandleColor: GlowColors.cyan,
    ),
  );
}
