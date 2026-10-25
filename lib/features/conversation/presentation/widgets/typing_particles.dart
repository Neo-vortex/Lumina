import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';

/// Typing indicator: three glowing motes that drift along a sine path and
/// leave fading particle trails (spec §9.3). Static dots under reduced motion.
class TypingParticles extends StatefulWidget {
  const TypingParticles({super.key, this.color = GlowColors.cyan, this.width = 34, this.height = 14});

  final Color color;
  final double width;
  final double height;

  @override
  State<TypingParticles> createState() => _TypingParticlesState();
}

class _TypingParticlesState extends State<TypingParticles> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.ambientEnabled(context)) {
      if (!_t.isAnimating) _t.repeat();
    } else {
      _t.value = 0.25;
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(widget.width, widget.height),
          painter: _ParticlePainter(_t, widget.color),
        ),
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.t, this.color) : super(repaint: t);

  final Animation<double> t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const motes = 3, trail = 5;
    for (var i = 0; i < motes; i++) {
      for (var k = trail; k >= 0; k--) {
        final phase = (t.value - i * 0.18 - k * 0.035) % 1.0;
        final x = size.width * (0.15 + 0.7 * (i / (motes - 1)));
        final y = size.height / 2 + math.sin(phase * 2 * math.pi) * size.height * 0.3;
        final alpha = k == 0 ? 0.95 : 0.35 * (1 - k / trail);
        final r = k == 0 ? 2.6 : 1.8 * (1 - k / (trail + 1));
        final paint = Paint()..color = color.withValues(alpha: alpha);
        if (k == 0) paint.maskFilter = const MaskFilter.blur(BlurStyle.solid, 2.5);
        canvas.drawCircle(Offset(x - k * 1.2, y), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => false;
}
