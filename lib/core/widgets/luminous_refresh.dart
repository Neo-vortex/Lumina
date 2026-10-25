import 'package:flutter/material.dart';

import '../theme/glow_colors.dart';
import '../theme/motion.dart';

/// Pull-to-refresh drawn as a luminous thread with a travelling shimmer
/// (spec §9.3), on top of the platform's own drag handling
/// ([RefreshIndicator.noSpinner]).
class LuminousRefresh extends StatefulWidget {
  const LuminousRefresh({super.key, required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<LuminousRefresh> createState() => _LuminousRefreshState();
}

class _LuminousRefreshState extends State<LuminousRefresh> with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  RefreshIndicatorStatus? _status;
  double _pull = 0;

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (Motion.ambientEnabled(context)) _shimmer.repeat();
    try {
      await widget.onRefresh();
    } finally {
      _shimmer.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _status == RefreshIndicatorStatus.refresh || _status == RefreshIndicatorStatus.snap;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is OverscrollNotification && n.overscroll < 0) {
              setState(() => _pull = (_pull - n.overscroll / 120).clamp(0.0, 1.0));
            } else if (n is ScrollEndNotification) {
              setState(() => _pull = 0);
            }
            return false;
          },
          child: RefreshIndicator.noSpinner(
            onRefresh: _refresh,
            onStatusChange: (s) => setState(() => _status = s),
            child: widget.child,
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Semantics(
              liveRegion: active,
              label: active ? 'Refreshing' : null,
              child: AnimatedOpacity(
                duration: Motion.micro,
                opacity:
                    active ||
                        _pull > 0 ||
                        _status == RefreshIndicatorStatus.drag ||
                        _status == RefreshIndicatorStatus.armed
                    ? 1
                    : 0,
                child: AnimatedBuilder(
                  animation: _shimmer,
                  builder: (context, _) => CustomPaint(
                    size: const Size(double.infinity, 4),
                    painter: _ThreadPainter(
                      extent: active ? 1 : (_status == RefreshIndicatorStatus.armed ? 1 : _pull),
                      shimmer: active ? _shimmer.value : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ThreadPainter extends CustomPainter {
  _ThreadPainter({required this.extent, required this.shimmer});

  final double extent;
  final double? shimmer;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * extent;
    final left = (size.width - w) / 2;
    final rect = Rect.fromLTWH(left, 0, w, 2.5);
    canvas.drawRect(
      rect.inflate(2),
      Paint()
        ..color = GlowColors.violet.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(colors: [GlowColors.cyan, GlowColors.violet, GlowColors.coral])
            .createShader(rect),
    );
    final s = shimmer;
    if (s != null) {
      final x = size.width * s;
      final spot = Rect.fromCenter(center: Offset(x, 1.25), width: size.width * 0.18, height: 2.5);
      canvas.drawRect(
        spot,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.9),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(spot),
      );
    }
  }

  @override
  bool shouldRepaint(_ThreadPainter old) => old.extent != extent || old.shimmer != shimmer;
}
