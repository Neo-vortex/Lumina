import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Height of a bar for [level] (0..1, already a perceptual loudness): the
/// absolute level, so bars don't jump when a louder sample enters the
/// window, with a small floor so silence still reads as a line.
double waveBarHeight(double level, double maxHeight) {
  final h = maxHeight * level.clamp(0.0, 1.0);
  return math.max(h, maxHeight * 0.08);
}

/// Moves [current] toward [target] over [dtMs]: fast attack, gentle decay.
double easeLevel({required double current, required double target, required double dtMs}) {
  final rate = target > current ? 0.025 : 0.01; // per millisecond
  final k = 1 - math.exp(-rate * dtMs);
  return current + (target - current) * k;
}

/// The live recording waveform: glowing rounded bars that scroll smoothly
/// between samples (they arrive every [sampleInterval]) while the newest
/// eases to its level. Repaints only itself, frame by frame, while shown.
class LiveWaveform extends StatefulWidget {
  const LiveWaveform({
    super.key,
    required this.levels,
    required this.color,
    this.height = 28,
    this.sampleInterval = const Duration(milliseconds: 80),
  });

  /// The recorder's levels so far (read every frame).
  final List<double> Function() levels;
  final Color color;
  final double height;
  final Duration sampleInterval;

  @override
  State<LiveWaveform> createState() => _LiveWaveformState();
}

class _LiveWaveformState extends State<LiveWaveform> with SingleTickerProviderStateMixin {
  final _paint = _WaveState();
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  int _seen = 0;
  Duration _sampleAt = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  void _tick(Duration now) {
    final dt = (now - _last).inMicroseconds / 1000.0;
    _last = now;
    final levels = widget.levels();
    if (levels.length != _seen) {
      _seen = levels.length;
      _sampleAt = now;
      _paint.settled.add(_paint.live);
      if (_paint.settled.length > 120) _paint.settled.removeAt(0);
    }
    final target = levels.isEmpty ? 0.0 : levels.last;
    _paint.live = easeLevel(current: _paint.live, target: target, dtMs: dt);
    _paint.shift = ((now - _sampleAt).inMicroseconds / widget.sampleInterval.inMicroseconds).clamp(0.0, 1.0);
    _paint.notify();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _paint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size(double.infinity, widget.height),
      painter: _WavePainter(_paint, widget.color),
    ),
  );
}

class _WaveState extends ChangeNotifier {
  final settled = <double>[];
  double live = 0;
  double shift = 0;

  void notify() => notifyListeners();
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.s, this.color) : super(repaint: s);

  final _WaveState s;
  final Color color;

  static const _bar = 3.0, _gap = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    const step = _bar + _gap;
    final mid = size.height / 2;
    final bars = [...s.settled, s.live];
    final glow = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final solid = Paint()..color = color;
    // Newest at the right edge; everything slides left as time passes.
    var x = size.width - _bar - s.shift * step;
    for (var i = bars.length - 1; i >= 0 && x > -_bar; i--, x -= step) {
      final h = waveBarHeight(bars[i], size.height);
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, mid - h / 2, _bar, h),
        const Radius.circular(_bar / 2),
      );
      // A soft halo under the loud bars.
      if (bars[i] > 0.25) canvas.drawRRect(r.inflate(1), glow);
      canvas.drawRRect(r, solid);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.color != color;
}
