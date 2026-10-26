import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/glow_colors.dart';
import '../theme/motion.dart';

/// Near-black backdrop with a few soft light orbs. Decorative: excluded
/// from semantics and frozen when the system asks for reduced motion
/// (UX-07, UX-10).
///
/// Still by default. On Impeller every animated pixel re-rasters the whole
/// screen (there is no raster cache), so a drifting backdrop behind a chat
/// kept the raster thread busy at the display rate while idle. Only screens
/// with nothing else moving (login, the call screen) set [drift].
class GlowBackground extends StatefulWidget {
  const GlowBackground({super.key, required this.child, this.drift = false});

  final Widget child;

  /// Let the orbs drift slowly (40 s loop).
  final bool drift;

  @override
  State<GlowBackground> createState() => _GlowBackgroundState();
}

class _GlowBackgroundState extends State<GlowBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(vsync: this, duration: Motion.drift);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.drift && Motion.ambientEnabled(context)) {
      if (!_drift.isAnimating) _drift.repeat();
    } else {
      _drift.stop();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          child: RepaintBoundary(child: CustomPaint(painter: _OrbPainter(_drift))),
        ),
        widget.child,
      ],
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.t) : super(repaint: t);

  final Animation<double> t;

  static const _orbs = [
    (color: GlowColors.teal, x: 0.15, y: 0.20, r: 0.55, phase: 0.0),
    (color: GlowColors.violet, x: 0.85, y: 0.35, r: 0.45, phase: 2.1),
    (color: GlowColors.coral, x: 0.40, y: 0.95, r: 0.50, phase: 4.2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [GlowColors.background, GlowColors.backgroundDeep],
        ).createShader(Offset.zero & size),
    );
    final angle = t.value * 2 * math.pi;
    for (final orb in _orbs) {
      final center = Offset(
        size.width * (orb.x + 0.06 * math.sin(angle + orb.phase)),
        size.height * (orb.y + 0.04 * math.cos(angle + orb.phase)),
      );
      final radius = size.shortestSide * orb.r;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [orb.color.withValues(alpha: 0.16), orb.color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbPainter oldDelegate) => false;
}
