import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/gestures.dart';

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

class _VideoNoteContentState extends State<VideoNoteContent> with SingleTickerProviderStateMixin {
  ({String source, bool local})? _playing;

  /// The player reports its position a few times a second; between reports
  /// the ring is extrapolated every frame so it runs smoothly.
  late final Ticker _ticker = createTicker(_tick);
  Duration _basePosition = Duration.zero;
  final _baseClock = Stopwatch();
  final _progress = ValueNotifier<double>(0);
  final _seek = ValueNotifier<Duration?>(null);

  /// The knob grows while it's held.
  final _grab = ValueNotifier<bool>(false);
  Duration _duration = Duration.zero;
  bool _scrubbing = false;

  void _tick(Duration _) {
    if (_playing == null || _scrubbing || _duration == Duration.zero) return;
    final at = _basePosition + _baseClock.elapsed;
    _progress.value = (at.inMicroseconds / _duration.inMicroseconds).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _progress.dispose();
    _seek.dispose();
    _grab.dispose();
    super.dispose();
  }

  void _scrub(Offset local, double size) {
    if (_playing == null || _duration == Duration.zero) return;
    final f = ringFraction(local, Size.square(size));
    _progress.value = f;
    _seek.value = _duration * f;
    _basePosition = _duration * f;
    _baseClock
      ..reset()
      ..start();
  }

  Future<void> _toggle() async {
    if (_playing != null) {
      _ticker.stop();
      _baseClock.stop();
      _progress.value = 0;
      setState(() => _playing = null);
      return;
    }
    _basePosition = Duration.zero;
    _baseClock
      ..reset()
      ..start();
    if (!_ticker.isActive) _ticker.start();
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
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: {
                TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  TapGestureRecognizer.new,
                  (t) => t.onTap = _toggle,
                ),
                // Touching the ring band while playing grabs it at once, ahead of
                // the list's scroll and swipe-to-reply, and drags along the ring.
                // Anywhere else (or when not playing) it steps aside.
                _RingGrabRecognizer: GestureRecognizerFactoryWithHandlers<_RingGrabRecognizer>(
                  _RingGrabRecognizer.new,
                  (g) => g
                    ..accepts = (local) {
                      if (_playing == null || _duration == Duration.zero) return false;
                      final r = (local - const Offset(size / 2, size / 2)).distance;
                      return r > size / 2 - 40 && r < size / 2 + 12;
                    }
                    ..onStart = (local) {
                      _scrubbing = true;
                      _grab.value = true;
                      HapticFeedback.selectionClick();
                      _scrub(local, size);
                    }
                    ..onUpdate = (local) {
                      _scrub(local, size);
                    }
                    ..onEnd = () {
                      _scrubbing = false;
                      _grab.value = false;
                    },
                ),
              },
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
                                      // Re-anchor the extrapolation on each report.
                                      _basePosition = position;
                                      _baseClock
                                        ..reset()
                                        ..start();
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
                        child: CustomPaint(
                          painter: _RingPainter(_progress, _grab, playing: _playing != null),
                        ),
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
  _RingPainter(this.progress, this.grab, {required this.playing})
    : super(repaint: Listenable.merge([progress, grab]));

  final ValueNotifier<double> progress;
  final ValueNotifier<bool> grab;
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
    if (!playing) return;
    final f = progress.value.clamp(0.0, 1.0);
    // The knob at the arc's end: where to grab to scrub.
    final angle = -math.pi / 2 + 2 * math.pi * f;
    final knob = rect.center + Offset(math.cos(angle), math.sin(angle)) * (rect.width / 2);
    final r = grab.value ? 9.0 : 6.0;
    void drawKnob() {
      canvas.drawCircle(
        knob,
        r + 5,
        Paint()
          ..color = GlowColors.cyan.withValues(alpha: grab.value ? 0.45 : 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(knob, r, Paint()..color = Colors.white);
      canvas.drawCircle(
        knob,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = GlowColors.cyan,
      );
    }

    if (f <= 0) return drawKnob();
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
    drawKnob();
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.playing != playing || old.progress != progress;
}

/// Claims a pointer the moment it lands where [accepts] says (the ring band of a
/// playing video), so the drag isn't lost to scrolling; elsewhere it rejects at
/// once and other gestures proceed as usual.
class _RingGrabRecognizer extends OneSequenceGestureRecognizer {
  bool Function(Offset local) accepts = (_) => false;
  void Function(Offset local)? onStart;
  void Function(Offset local)? onUpdate;
  VoidCallback? onEnd;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    final local = event.localPosition;
    if (!accepts(local)) return;
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
    onStart?.call(local);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      onUpdate?.call(event.localPosition);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      onEnd?.call();
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'ring grab';
}
