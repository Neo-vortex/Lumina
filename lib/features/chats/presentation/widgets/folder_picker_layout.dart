import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Geometry of the folder gesture picker: a column of [count] slots on one
/// screen edge, the slot under the finger, how strongly each name reacts to
/// the finger (fisheye), the cancel zone and edge auto-scroll.
class FolderPickerLayout {
  FolderPickerLayout({
    required this.screen,
    required this.padding,
    required this.count,
    required this.rightEdge,
    double scroll = 0,
  }) : scroll = scroll.clamp(0, _maxScroll(screen, padding, count));

  static const slot = 56.0;
  static const edgeZone = 64.0;
  static const cancelFraction = 0.4;
  static const maxScrollSpeed = 900.0;
  static const _inset = 28.0;

  final Size screen;
  final EdgeInsets padding;
  final int count;
  final bool rightEdge;
  final double scroll;

  static bool rightEdgeFor(double pressX, double width) => pressX > width / 2;

  static double _visible(Size s, EdgeInsets p) => s.height - p.vertical;
  static double _maxScroll(Size s, EdgeInsets p, int n) => math.max(0, n * slot - _visible(s, p));

  double get maxScroll => _maxScroll(screen, padding, count);

  /// The x the names line up on.
  double get listX => rightEdge ? screen.width - _inset : _inset;

  double get top {
    final visible = _visible(screen, padding);
    final height = count * slot;
    return padding.top + (height < visible ? (visible - height) / 2 : 0) - scroll;
  }

  double centerOf(int i) => top + slot * i + slot / 2;

  int indexAt(double y) => ((y - top) / slot).floor().clamp(0, math.max(0, count - 1));

  bool isCancel(Offset finger) => (finger.dx - listX).abs() > cancelFraction * screen.width;

  /// 0…1: how much slot [i] lights up, lean and scale, for [finger].
  double focus(int i, Offset finger) {
    final dy = (centerOf(i) - finger.dy) / (slot * 1.5);
    final vertical = math.exp(-dy * dy);
    final sideways = 1 - ((finger.dx - listX).abs() / (cancelFraction * screen.width)).clamp(0.0, 1.0);
    return vertical * (0.35 + 0.65 * sideways);
  }

  /// Pixels per second to scroll (negative = up) while the finger rests
  /// near the top or bottom of a list taller than the screen.
  double scrollVelocity(double y) {
    if (maxScroll == 0) return 0;
    final fromTop = y - padding.top;
    final fromBottom = screen.height - padding.bottom - y;
    if (fromBottom < edgeZone) return maxScrollSpeed * (1 - fromBottom.clamp(0, edgeZone) / edgeZone);
    if (fromTop < edgeZone) return -maxScrollSpeed * (1 - fromTop.clamp(0, edgeZone) / edgeZone);
    return 0;
  }

  FolderPickerLayout withScroll(double scroll) => FolderPickerLayout(
    screen: screen,
    padding: padding,
    count: count,
    rightEdge: rightEdge,
    scroll: scroll,
  );
}
