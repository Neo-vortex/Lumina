import 'package:flutter/material.dart';

/// "Glowing Relaxation" palette. Deliberately not Telegram's blue/white.
///
/// Contrast ratios are documented in docs/UX_RESEARCH.md §1. Rule of thumb:
/// the bright accents are for glows and non-text marks; text on an accent
/// gradient uses [onAccent], or one of the darkened gradients.
abstract final class GlowColors {
  // Base (spec range #0D0F12 → #050607; pure black avoided, UX-05).
  static const background = Color(0xFF0D0F12);
  static const backgroundDeep = Color(0xFF07090B);
  static const surface = Color(0xFF14171C);
  static const surfaceHigh = Color(0xFF1C2027);

  /// Decorative dividers only (1.3 : 1).
  static const outline = Color(0xFF262B33);

  /// Boundaries of interactive controls, ≥ 3 : 1 on [surface] (UX-03).
  static const outlineStrong = Color(0xFF5E6878);

  static const text = Color(0xFFE6EAF0);
  static const textMuted = Color(0xFF8B95A4);
  static const error = Color(0xFFFF7A8A);

  /// Text on bright accent fills (amber, coral, cyan, teal) (UX-01).
  static const onAccent = Color(0xFF0D0F12);

  // Incoming: cool cyan -> teal.
  static const cyan = Color(0xFF4FE3DC);
  static const teal = Color(0xFF1C9AAE);

  // Outgoing: warm amber -> coral.
  static const amber = Color(0xFFFFB850);
  static const coral = Color(0xFFFF6E66);

  // Active / selection: violet -> magenta. Bright variants for glow only.
  static const violet = Color(0xFF9A5CFF);
  static const magenta = Color(0xFFE052D6);
  // Darkened for white text (5.9 / 5.8 : 1) (UX-02).
  static const violetDeep = Color(0xFF7440E0);
  static const magentaDeep = Color(0xFFA83599);

  static const incoming = LinearGradient(
    colors: [cyan, teal],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const outgoing = LinearGradient(
    colors: [amber, coral],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Primary actions with white labels.
  static const active = LinearGradient(
    colors: [violetDeep, magentaDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Soft outer glow: accent at 20–30 % opacity, blur 12–20 (spec §9.1).
/// Decoration only; never the sole state cue (UX-04).
List<BoxShadow> glow(Color color, {double intensity = 1}) {
  final t = intensity.clamp(0.0, 1.0);
  return [
    BoxShadow(
      color: color.withValues(alpha: 0.20 + 0.10 * t),
      blurRadius: 12 + 8 * t,
      spreadRadius: 0.5 * t,
    ),
  ];
}
