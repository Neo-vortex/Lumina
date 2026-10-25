import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../domain/story_decoration.dart';

/// The 9:16 editing surface: [media] letterboxed underneath, decorations on
/// top. Drag to move, pinch to resize, twist to rotate, drop on the bin to
/// delete, tap text to edit it.
class StoryCanvas extends StatefulWidget {
  const StoryCanvas({
    super.key,
    required this.media,
    required this.decorations,
    required this.onChanged,
    this.onEditText,
  });

  final Widget media;
  final List<StoryDecoration> decorations;
  final VoidCallback onChanged;
  final void Function(TextSticker sticker)? onEditText;

  @override
  State<StoryCanvas> createState() => _StoryCanvasState();
}

class _StoryCanvasState extends State<StoryCanvas> {
  StoryDecoration? _active;
  Offset _startCenter = Offset.zero;
  Offset _startFocal = Offset.zero;
  double _startScale = 1;
  double _startRotation = 0;
  var _overBin = false;

  StoryDecoration? _hit(Offset p, Size frame) {
    for (final d in widget.decorations.reversed) {
      if (DecorationPainter.boundsOf(d, frame).inflate(12).contains(p)) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 9 / 16,
    child: LayoutBuilder(
      builder: (context, c) {
        final frame = c.biggest;
        final binCenter = Offset(frame.width / 2, frame.height - 44);
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (t) {
              final d = _hit(t.localPosition, frame);
              if (d is TextSticker) widget.onEditText?.call(d);
            },
            onScaleStart: (s) {
              final d = _hit(s.localFocalPoint, frame);
              if (d == null) return;
              setState(() => _active = d);
              // Bring to front.
              widget.decorations
                ..remove(d)
                ..add(d);
              _startCenter = d.center;
              _startFocal = s.localFocalPoint;
              _startScale = d.scale;
              _startRotation = d.rotation;
            },
            onScaleUpdate: (s) {
              final d = _active;
              if (d == null) return;
              final delta = s.localFocalPoint - _startFocal;
              d
                ..center = Offset(
                  (_startCenter.dx + delta.dx / frame.width).clamp(0.0, 1.0),
                  (_startCenter.dy + delta.dy / frame.height).clamp(0.0, 1.0),
                )
                ..scale = (_startScale * s.scale).clamp(0.3, 4.0)
                ..rotation = _startRotation + s.rotation;
              final over = (s.localFocalPoint - binCenter).distance < 48;
              if (over != _overBin) HapticFeedback.selectionClick();
              setState(() => _overBin = over);
            },
            onScaleEnd: (_) {
              final d = _active;
              if (d != null && _overBin) widget.decorations.remove(d);
              setState(() {
                _active = null;
                _overBin = false;
              });
              widget.onChanged();
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: Colors.black, child: widget.media),
                CustomPaint(painter: _Painter(widget.decorations, _active)),
                if (_active != null)
                  Positioned(
                    left: binCenter.dx - 26,
                    top: binCenter.dy - 26,
                    child: AnimatedScale(
                      scale: _overBin ? 1.25 : 1,
                      duration: const Duration(milliseconds: 120),
                      child: CircleAvatar(
                        radius: 26,
                        backgroundColor: _overBin ? GlowColors.coral : Colors.black54,
                        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _Painter extends CustomPainter {
  _Painter(this.decorations, this.active);

  final List<StoryDecoration> decorations;
  final StoryDecoration? active;

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in decorations) {
      DecorationPainter.paint(canvas, size, d);
      if (!d.burned) {
        // Mark tags that viewers' apps draw (and tap) themselves.
        final b = DecorationPainter.boundsOf(d, size);
        canvas.drawCircle(b.topRight, 6, Paint()..color = GlowColors.cyan);
      }
    }
  }

  @override
  bool shouldRepaint(_Painter old) => true;
}
