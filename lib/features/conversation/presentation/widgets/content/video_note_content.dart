import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../../core/media/tdlib_stream_server.dart';
import '../../../../../core/telegram/display.dart';
import '../../../../../core/telegram/file_store.dart';
import '../../../../../core/telegram/widgets/td_file_image.dart';
import '../../../../../core/theme/glow_colors.dart';
import '../../../../media/presentation/widgets/video_player_view.dart';
import '../../../bloc/conversation_cubit.dart';

/// Where on the ring [local] points, as 0..1 clockwise from the top.
double ringFraction(Offset local, Size size) {
  final d = local - size.center(Offset.zero);
  final angle = math.atan2(d.dx, -d.dy); // 0 at the top, clockwise positive
  return (angle < 0 ? angle + 2 * math.pi : angle) / (2 * math.pi);
}

/// Round video message: just the circle, like Telegram (no bubble). Tap
/// plays inline (streamed if needed), tap again stops; while playing, a
/// glowing progress arc runs round the edge and dragging along it seeks.
class VideoNoteContent extends StatefulWidget {
  const VideoNoteContent({super.key, required this.message, required this.note, required this.footer});

  final td.Message message;
  final td.VideoNote note;
  final Widget footer;

  @override
  State<VideoNoteContent> createState() => _VideoNoteContentState();
}

class _VideoNoteContentState extends State<VideoNoteContent> {
  ({String source, bool local})? _playing;
  final _progress = ValueNotifier<double>(0);
  final _seek = ValueNotifier<Duration?>(null);
  Duration _duration = Duration.zero;
  bool _scrubbing = false;

  @override
  void dispose() {
    _progress.dispose();
    _seek.dispose();
    super.dispose();
  }

  void _scrub(Offset local, double size) {
    if (_playing == null || _duration == Duration.zero) return;
    final f = ringFraction(local, Size.square(size));
    _progress.value = f;
    _seek.value = _duration * f;
  }

  Future<void> _toggle() async {
    if (_playing != null) {
      _progress.value = 0;
      setState(() => _playing = null);
      return;
    }
    final files = context.read<FileStore>();
    final stream = context.read<TdStreamServer>();
    final f = files[widget.note.video.id] ?? widget.note.video;
    if (f.local.isDownloadingCompleted) {
      setState(() => _playing = (source: f.local.path, local: true));
    } else {
      final url = await stream.urlFor(f, mimeType: 'video/mp4');
      if (mounted) setState(() => _playing = (source: url.toString(), local: false));
    }
    if (!widget.message.isOutgoing && mounted) {
      context.read<ConversationCubit>().openViewOnce(widget.message).ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    const size = 210.0;
    final thumb = widget.note.thumbnail?.file;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: 'Video message, ${Display.duration(widget.note.duration)}',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: _toggle,
              // Dragging near the edge while playing scrubs along the ring.
              // Only while playing, so swipe-to-reply still works otherwise.
              onPanStart: _playing == null
                  ? null
                  : (d) {
                      final r = (d.localPosition - const Offset(size / 2, size / 2)).distance;
                      _scrubbing = r > size / 2 - 36;
                      if (_scrubbing) _scrub(d.localPosition, size);
                    },
              onPanUpdate: _playing == null
                  ? null
                  : (d) {
                      if (_scrubbing) _scrub(d.localPosition, size);
                    },
              onPanEnd: _playing == null ? null : (_) => _scrubbing = false,
              child: SizedBox.square(
                dimension: size,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: glow(GlowColors.cyan, intensity: _playing != null ? 0.9 : 0.3),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: ClipOval(
                          child: _playing != null
                              ? VideoPlayerView(
                                  source: _playing!.source,
                                  isLocalFile: _playing!.local,
                                  aspectRatio: 1,
                                  showControls: false,
                                  seek: _seek,
                                  onProgress: (position, duration, ended) {
                                    _duration = duration;
                                    if (ended) {
                                      _toggle();
                                    } else if (!_scrubbing && duration > Duration.zero) {
                                      _progress.value = position.inMilliseconds / duration.inMilliseconds;
                                    }
                                  },
                                )
                              : Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (thumb != null)
                                      TdFileImage(
                                        file: thumb,
                                        placeholderBytes: Display.minithumbnail(widget.note.minithumbnail),
                                      )
                                    else
                                      Container(color: GlowColors.surfaceHigh),
                                    const Center(
                                      child: Icon(Icons.play_arrow_rounded, size: 48, color: Colors.white),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(painter: _RingPainter(_progress, playing: _playing != null)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // The time sits in a small pill: there's no bubble behind it.
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: widget.footer,
            ),
          ),
        ],
      ),
    );
  }
}

/// The track and glowing progress arc round a round video.
class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, {required this.playing}) : super(repaint: progress);

  final ValueNotifier<double> progress;
  final bool playing;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = GlowColors.cyan.withValues(alpha: playing ? 0.25 : 0.8),
    );
    if (!playing || progress.value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.value.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = GlowColors.cyan,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.playing != playing || old.progress != progress;
}
