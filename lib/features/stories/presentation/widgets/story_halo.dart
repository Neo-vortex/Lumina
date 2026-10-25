import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';

/// A ring around an avatar that marks active stories: a slowly turning
/// violet→cyan sweep that breathes while stories are unseen, and a quiet
/// outline once they have all been watched.
class StoryHalo extends StatefulWidget {
  const StoryHalo({super.key, required this.child, required this.size, required this.unseen, this.onTap});

  final Widget child;

  /// Diameter of [child].
  final double size;
  final bool unseen;
  final VoidCallback? onTap;

  @override
  State<StoryHalo> createState() => _StoryHaloState();
}

class _StoryHaloState extends State<StoryHalo> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: Motion.drift ~/ 4);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(StoryHalo oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate =
        widget.unseen &&
        !(WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations);
    if (animate && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!animate) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outer = widget.size + 8;
    return Semantics(
      button: widget.onTap != null,
      label: widget.unseen ? 'New stories' : 'Stories',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox.square(
          dimension: outer,
          child: AnimatedBuilder(
            animation: _spin,
            builder: (context, child) => CustomPaint(
              painter: _HaloPainter(turn: _spin.value, unseen: widget.unseen),
              child: child,
            ),
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _HaloPainter extends CustomPainter {
  _HaloPainter({required this.turn, required this.unseen});

  final double turn;
  final bool unseen;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(1.4);
    if (!unseen) {
      canvas.drawOval(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = GlowColors.outlineStrong,
      );
      return;
    }
    final breath = 0.5 + 0.5 * math.sin(turn * 2 * math.pi * 2);
    final shader = SweepGradient(
      colors: const [GlowColors.violet, GlowColors.cyan, GlowColors.magenta, GlowColors.violet],
      transform: GradientRotation(turn * 2 * math.pi),
    ).createShader(rect);
    canvas.drawOval(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..shader = shader
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 3 * breath),
    );
    canvas.drawOval(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.turn != turn || old.unseen != unseen;
}

/// Progress ring around the poster's avatar in the viewer (bottom left):
/// one arc per story, the current one filling with [progress].
class StoryProgressRing extends StatelessWidget {
  const StoryProgressRing({
    super.key,
    required this.child,
    required this.size,
    required this.count,
    required this.index,
    required this.progress,
  });

  final Widget child;
  final double size;
  final int count;
  final int index;
  final double progress;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size + 10,
    child: CustomPaint(
      painter: _RingPainter(count: count, index: index, progress: progress),
      child: Center(child: child),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.count, required this.index, required this.progress});

  final int count;
  final int index;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    final n = math.max(count, 1);
    final gap = n == 1 ? 0.0 : 0.12;
    final sweep = 2 * math.pi / n - gap;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Colors.white24;
    final lit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(colors: [GlowColors.cyan, GlowColors.violet, GlowColors.cyan])
          .createShader(rect);
    for (var i = 0; i < n; i++) {
      final start = -math.pi / 2 + i * (sweep + gap) + gap / 2;
      canvas.drawArc(rect, start, sweep, false, base);
      final fill = i < index ? 1.0 : (i == index ? progress.clamp(0.0, 1.0) : 0.0);
      if (fill > 0) canvas.drawArc(rect, start, sweep * fill, false, lit);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.count != count || old.index != index || old.progress != progress;
}
