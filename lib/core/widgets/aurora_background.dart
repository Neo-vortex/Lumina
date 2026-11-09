import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/glow_colors.dart';
import '../theme/motion.dart';

/// The chat list's backdrop: large, soft violet / cyan / magenta glows that
/// hug the edges, so the middle (where names and previews sit) stays calm.
///
/// [drift] moves them slowly. On Impeller every repaint re-rasters the
/// screen, so the drift runs off a 12 fps timer rather than a vsync ticker
/// (a 90-second loop barely moves per step, so it still reads as smooth),
/// and stops whenever the screen is hidden (another tab, a pushed route),
/// the app is in the background, or the system asks for reduced motion.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, required this.child, this.drift = true});

  final Widget child;
  final bool drift;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with WidgetsBindingObserver {
  static const _loop = Duration(seconds: 90);
  static const _step = Duration(milliseconds: 83);

  final _phase = ValueNotifier<double>(0);
  final _clock = Stopwatch();
  Timer? _timer;
  ValueListenable<bool>? _tickerMode;
  var _resumed = true;

  /// A list under it is scrolling: hold the drift so the frame only has the
  /// list to redraw.
  var _scrolling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mode = TickerMode.getNotifier(context);
    if (!identical(mode, _tickerMode)) {
      _tickerMode?.removeListener(_sync);
      _tickerMode = mode..addListener(_sync);
    }
    _sync();
  }

  @override
  void didUpdateWidget(AuroraBackground old) {
    super.didUpdateWidget(old);
    if (old.drift != widget.drift) _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    final run =
        widget.drift &&
        _resumed &&
        !_scrolling &&
        (_tickerMode?.value ?? true) &&
        Motion.ambientEnabled(context);
    if (run && _timer == null) {
      _clock.start();
      _timer = Timer.periodic(_step, (_) {
        _phase.value = (_clock.elapsedMilliseconds % _loop.inMilliseconds) / _loop.inMilliseconds;
      });
    } else if (!run && _timer != null) {
      _timer!.cancel();
      _timer = null;
      _clock.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickerMode?.removeListener(_sync);
    _timer?.cancel();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ExcludeSemantics(
        child: RepaintBoundary(child: CustomPaint(painter: _AuroraPainter(_phase))),
      ),
      NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollStartNotification && !_scrolling) {
            _scrolling = true;
            _sync();
          } else if (n is ScrollEndNotification && _scrolling) {
            _scrolling = false;
            _sync();
          }
          return false;
        },
        child: widget.child,
      ),
    ],
  );
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t) : super(repaint: t);

  final ValueListenable<double> t;

  // x / y as fractions of the screen, r of its shorter side; drift radius
  // dx / dy and phase per glow.
  static const _glows = [
    (color: GlowColors.violet, x: -0.05, y: 0.08, r: 0.95, a: 0.26, dx: 0.10, dy: 0.05, p: 0.0),
    (color: GlowColors.cyan, x: 1.05, y: 0.42, r: 0.80, a: 0.16, dx: 0.08, dy: 0.07, p: 2.1),
    (color: GlowColors.magenta, x: 0.25, y: 1.02, r: 0.95, a: 0.20, dx: 0.12, dy: 0.04, p: 4.2),
    (color: GlowColors.teal, x: 0.95, y: 0.95, r: 0.60, a: 0.14, dx: 0.06, dy: 0.06, p: 1.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [GlowColors.background, GlowColors.backgroundDeep],
        ).createShader(rect),
    );
    final angle = t.value * 2 * math.pi;
    for (final g in _glows) {
      final center = Offset(
        size.width * (g.x + g.dx * math.sin(angle + g.p)),
        size.height * (g.y + g.dy * math.cos(angle * 2 + g.p)),
      );
      // Breathes a little as it drifts.
      final radius = size.shortestSide * g.r * (1 + 0.06 * math.sin(angle * 3 + g.p));
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              g.color.withValues(alpha: g.a),
              g.color.withValues(alpha: g.a * 0.35),
              g.color.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
    // A soft calm band down the middle, where the text sits.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.transparent, GlowColors.background.withValues(alpha: 0.35), Colors.transparent],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => false;
}
