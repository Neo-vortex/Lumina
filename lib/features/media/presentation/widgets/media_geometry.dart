import 'dart:math' as math;
import 'dart:ui';

/// Geometry for the media viewer's gestures and flights, apart from widgets
/// so it can be tested.

/// The largest rect of [aspect] (w / h) inside [box], centred.
Rect containRect(double aspect, Rect box) {
  final a = aspect <= 0 ? 1.0 : aspect;
  final w = math.min(box.width, box.height * a);
  return Rect.fromCenter(center: box.center, width: w, height: w / a);
}

/// The smallest rect of [aspect] covering [box], centred (what a tile shows
/// cropped).
Rect coverRect(double aspect, Rect box) {
  final a = aspect <= 0 ? 1.0 : aspect;
  final w = math.max(box.width, box.height * a);
  return Rect.fromCenter(center: box.center, width: w, height: w / a);
}

/// Scale about the origin, then [offset]: screen = offset + scale * point.
class Zoom {
  const Zoom({required this.scale, required this.offset});

  static const identity = Zoom(scale: 1, offset: Offset.zero);

  final double scale;
  final Offset offset;

  bool get zoomed => scale > 1.01;

  Offset apply(Offset p) => offset + p * scale;

  Rect applyRect(Rect r) => Rect.fromPoints(apply(r.topLeft), apply(r.bottomRight));

  /// [start] was the zoom when two fingers landed at [startFocal]; the
  /// content point that was under them stays under [focal].
  Zoom pinch({required Zoom start, required Offset startFocal, required Offset focal, required double scale}) {
    final s = start.scale * scale;
    final content = (startFocal - start.offset) / start.scale;
    return Zoom(scale: s, offset: focal - content * s);
  }

  /// Within [1, max], and the content covers the screen where it can,
  /// centred where it can't.
  Zoom settled(Rect content, Size screen, {required double max}) {
    final s = scale.clamp(1.0, max);
    if (s <= 1.0001) return identity;
    var o = offset;
    final r = Rect.fromPoints(o + content.topLeft * s, o + content.bottomRight * s);
    double fit(double lo, double hi, double extent, double at) {
      if (hi - lo <= extent) return at + (extent - (hi - lo)) / 2 - lo;
      if (lo > 0) return at - lo;
      if (hi < extent) return at + (extent - hi);
      return at;
    }

    o = Offset(fit(r.left, r.right, screen.width, o.dx), fit(r.top, r.bottom, screen.height, o.dy));
    return Zoom(scale: s, offset: o);
  }

  @override
  bool operator ==(Object other) => other is Zoom && other.scale == scale && other.offset == offset;

  @override
  int get hashCode => Object.hash(scale, offset);

  @override
  String toString() => 'Zoom($scale, $offset)';

  static Zoom lerp(Zoom a, Zoom b, double t) =>
      Zoom(scale: lerpDouble(a.scale, b.scale, t)!, offset: Offset.lerp(a.offset, b.offset, t)!);
}

/// Past [min]/[max] the value follows with growing resistance.
double rubberBand(double v, {required double min, required double max}) {
  double damp(double over, double limit) => limit * (1 - 1 / (over / limit + 1));
  if (v < min) return min - damp(min - v, min * 0.5);
  if (v > max) return max + damp(v - max, max * 0.5);
  return v;
}

/// Closes on a drag past 18 % of the height or a flick (px/s) the same way.
bool shouldDismiss({required double offset, required double velocity, required double height}) {
  if (velocity.abs() > 900 && velocity.sign == offset.sign) return true;
  return offset.abs() > height * 0.18 && !(velocity.abs() > 900 && velocity.sign != offset.sign);
}

/// The page to settle on from a gallery [position] (in pages); a positive
/// [velocity] (px/s) heads for the next page.
int settlePage({required double position, required double velocity, required int count}) {
  final base = position.floor();
  int target;
  if (velocity > 400) {
    target = base + 1;
  } else if (velocity < -400) {
    target = position.ceil() - 1;
  } else {
    target = position.round();
  }
  return target.clamp(0, count - 1);
}

/// One frame of a flight between a tile and the full view: [clip] is the
/// visible window, [image] where the whole picture is drawn under it.
({Rect clip, Rect image}) flightFrame({
  required double t,
  required double aspect,
  required Rect from,
  required Rect to,
}) => (
  clip: Rect.lerp(from, to, t)!,
  image: Rect.lerp(coverRect(aspect, from), to, t)!,
);
