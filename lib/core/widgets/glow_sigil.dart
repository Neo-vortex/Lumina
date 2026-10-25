import 'package:flutter/material.dart';

import '../theme/glow_colors.dart';

/// The app mark: a soft ring sweeping through the incoming, active and
/// outgoing hues. Decorative.
class GlowSigil extends StatelessWidget {
  const GlowSigil({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(
            colors: [GlowColors.cyan, GlowColors.violet, GlowColors.coral, GlowColors.amber, GlowColors.cyan],
          ),
          boxShadow: [...glow(GlowColors.violet), ...glow(GlowColors.cyan, intensity: 0.3)],
        ),
        child: Center(
          child: Container(
            width: size * 0.62,
            height: size * 0.62,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: GlowColors.background),
          ),
        ),
      ),
    );
  }
}
