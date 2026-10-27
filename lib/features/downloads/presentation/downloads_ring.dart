import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/glow_colors.dart';
import '../../../core/widgets/smooth_progress.dart';
import '../bloc/downloads_cubit.dart';

/// The chat list header's downloads button: a ring that fills with the
/// active downloads' progress; hidden while nothing downloads.
class DownloadsRing extends StatelessWidget {
  const DownloadsRing({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => BlocBuilder<DownloadsCubit, DownloadsState>(
    buildWhen: (a, b) =>
        a.active.length != b.active.length ||
        a.downloadedSize != b.downloadedSize ||
        a.totalSize != b.totalSize ||
        a.active.every((i) => i.isPaused) != b.active.every((i) => i.isPaused),
    builder: (context, state) {
      if (!state.anyActive) return const SizedBox.shrink();
      final paused = state.active.every((i) => i.isPaused);
      final progress = state.totalSize > 0 ? (state.downloadedSize / state.totalSize).clamp(0.0, 1.0) : 0.0;
      final percent = (progress * 100).round();
      final color = paused ? GlowColors.amber : GlowColors.cyan;
      return Semantics(
        button: true,
        label: 'Downloads, ${state.active.length} active, $percent%',
        excludeSemantics: true,
        child: InkResponse(
          onTap: onOpen,
          radius: 24,
          child: SizedBox.square(
            dimension: 48,
            child: Center(
              child: SizedBox.square(
                dimension: 30,
                child: SmoothProgress(
                  value: progress,
                  builder: (context, v) => CustomPaint(
                    painter: _RingPainter(progress: v!, color: color),
                    child: Icon(
                      paused ? Icons.pause_rounded : Icons.arrow_downward_rounded,
                      size: 16,
                      color: color,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = GlowColors.outline,
    );
    if (progress <= 0) return;
    final sweep = math.pi * 2 * progress;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}
