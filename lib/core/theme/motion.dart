import 'package:flutter/material.dart';

/// Motion vocabulary mapped onto Material 3 tokens ([Durations], [Easing])
/// so widgets never carry ad-hoc timings (UX-09).
abstract final class Motion {
  // Content changes: fast, M3 tokens.
  static const micro = Durations.short4; // 200 ms: focus, error reveal
  static const standard = Durations.medium2; // 300 ms: toggles, field swaps
  static const screen = Durations.long1; // 450 ms: auth step changes

  static const enter = Easing.emphasizedDecelerate;
  static const exit = Easing.emphasizedAccelerate;
  static const move = Easing.standard;

  // Ambient "relaxation" loops: slow and low amplitude (UX-11).
  static const breath = Duration(milliseconds: 2600);
  static const pulse = Duration(milliseconds: 1800);
  static const drift = Duration(seconds: 40);

  /// Whether ambient / decorative motion should run (UX-10).
  static bool ambientEnabled(BuildContext context) => !MediaQuery.disableAnimationsOf(context);
}
