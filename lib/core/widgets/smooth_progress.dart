import 'package:flutter/widgets.dart';

/// Eases a progress value toward each new reading, so bars and rings glide
/// instead of jumping with every chunk TDLib or an encoder reports. A new
/// reading mid-glide continues from where the bar is. `null` (unknown)
/// passes straight through.
class SmoothProgress extends StatelessWidget {
  const SmoothProgress({super.key, required this.value, required this.builder});

  final double? value;
  final Widget Function(BuildContext context, double? value) builder;

  static const duration = Duration(milliseconds: 380);

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v == null) return builder(context, null);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: v.clamp(0.0, 1.0)),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, shown, _) => builder(context, shown),
    );
  }
}
