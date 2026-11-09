import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

/// Where an outgoing message is: still sending, sent, or read.
enum TickState { sending, sent, read }

/// Classic delivery ticks: a clock while sending, one tick once sent, two
/// once read (the second in [readColor]). Only a change animates — the new
/// tick draws its stroke in with a small pop — so scrolling past old
/// messages stays still.
class DeliveryTicks extends StatefulWidget {
  const DeliveryTicks({
    super.key,
    required this.state,
    required this.color,
    required this.readColor,
    this.size = 14,
  });

  final TickState state;
  final Color color;
  final Color readColor;
  final double size;

  @override
  State<DeliveryTicks> createState() => _DeliveryTicksState();
}

class _DeliveryTicksState extends State<DeliveryTicks> with SingleTickerProviderStateMixin {
  late final _ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 380), value: 1);

  @override
  void didUpdateWidget(DeliveryTicks old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state && widget.state != TickState.sending) _ctl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.size * 1.3;
    if (widget.state == TickState.sending) {
      return SizedBox(
        width: w,
        height: widget.size,
        child: Icon(Icons.schedule_rounded, size: widget.size * 0.85, color: widget.color),
      );
    }
    return AnimatedBuilder(
      animation: _ctl,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_ctl.value);
        // A short overshoot as the stroke completes.
        final pop = 1 + 0.18 * Curves.easeOut.transform((1 - (2 * _ctl.value - 1).abs()).clamp(0, 1));
        return Transform.scale(
          scale: pop,
          child: CustomPaint(
            size: Size(w, widget.size),
            painter: _TicksPainter(
              read: widget.state == TickState.read,
              progress: t,
              color: widget.state == TickState.read
                  ? Color.lerp(widget.color, widget.readColor, t)!
                  : widget.color,
            ),
          ),
        );
      },
    );
  }
}

class _TicksPainter extends CustomPainter {
  _TicksPainter({required this.read, required this.progress, required this.color});

  final bool read;

  /// 0–1: how much of the newest tick is drawn.
  final double progress;
  final Color color;

  Path _tick(Size s, double dx) => Path()
    ..moveTo(s.width * 0.08 + dx, s.height * 0.55)
    ..lineTo(s.width * 0.3 + dx, s.height * 0.78)
    ..lineTo(s.width * 0.68 + dx, s.height * 0.24);

  void _draw(Canvas canvas, Path path, double fraction, Paint paint) {
    if (fraction >= 1) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final PathMetric m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * fraction), paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.13
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final shift = size.width * 0.24;
    if (read) {
      // The first tick is already there; the second draws in beside it.
      _draw(canvas, _tick(size, 0), 1, paint);
      _draw(canvas, _tick(size, shift), progress, paint);
    } else {
      _draw(canvas, _tick(size, shift / 2), progress, paint);
    }
  }

  @override
  bool shouldRepaint(_TicksPainter old) => old.read != read || old.progress != progress || old.color != color;
}
