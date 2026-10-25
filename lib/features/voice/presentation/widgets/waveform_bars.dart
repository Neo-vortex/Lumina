import 'package:flutter/material.dart';

import '../../../../core/media/waveform.dart';

/// Rounded waveform bars; bars before [progress] use [activeColor].
class WaveformBars extends StatelessWidget {
  const WaveformBars({
    super.key,
    required this.values,
    required this.color,
    required this.activeColor,
    this.progress = 0,
    this.height = 30,
    this.onSeek,
  });

  final List<int> values;
  final Color color;
  final Color activeColor;
  final double progress;
  final double height;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final paint = CustomPaint(
          size: Size(c.maxWidth, height),
          painter: _BarsPainter(values: values, color: color, active: activeColor, progress: progress),
        );
        if (onSeek == null) return ExcludeSemantics(child: paint);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => onSeek!((d.localPosition.dx / c.maxWidth).clamp(0, 1)),
          onHorizontalDragUpdate: (d) => onSeek!((d.localPosition.dx / c.maxWidth).clamp(0, 1)),
          child: ExcludeSemantics(child: paint),
        );
      },
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.values, required this.color, required this.active, required this.progress});

  final List<int> values;
  final Color color;
  final Color active;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const gap = 2.0;
    final count = ((size.width + gap) / 5).floor().clamp(8, 120);
    final bars = Waveform.resample(values, count);
    final w = (size.width - gap * (count - 1)) / count;
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final h = (bars[i] / Waveform.maxValue) * (size.height - 4) + 3;
      final x = i * (w + gap);
      paint.color = (i + 0.5) / count <= progress ? active : color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, (size.height - h) / 2, w, h), Radius.circular(w / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values || old.progress != progress || old.color != color || old.active != active;
}
