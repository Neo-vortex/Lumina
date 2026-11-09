import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/media/presentation/widgets/media_geometry.dart';

void main() {
  const screen = Size(400, 800);

  test('contain and cover keep the aspect ratio', () {
    expect(containRect(2, Offset.zero & screen), const Rect.fromLTWH(0, 300, 400, 200));
    expect(coverRect(2, const Rect.fromLTWH(0, 0, 100, 100)), const Rect.fromLTWH(-50, 0, 200, 100));
  });

  test('a pinch keeps the point under the fingers under the fingers', () {
    const z = Zoom.identity;
    final p = z.pinch(start: z, startFocal: const Offset(100, 400), focal: const Offset(100, 400), scale: 2);
    expect(p.scale, 2);
    expect(p.apply(const Offset(100, 400)), const Offset(100, 400));
    // Moving the fingers pans with them.
    final moved = z.pinch(
      start: z,
      startFocal: const Offset(100, 400),
      focal: const Offset(130, 380),
      scale: 2,
    );
    expect(moved.apply(const Offset(100, 400)), const Offset(130, 380));
  });

  test('settled zoom stays inside limits and never shows past the image edges', () {
    const content = Rect.fromLTWH(0, 300, 400, 200);
    final tooFar = const Zoom(scale: 2, offset: Offset(150, 0)).settled(content, screen, max: 5);
    final r = tooFar.applyRect(content);
    expect(r.left, 0, reason: 'wider than the screen: edge pinned');
    expect(r.center.dy, closeTo(400, 0.001), reason: 'shorter than the screen: centred');
    expect(const Zoom(scale: 0.6, offset: Offset(10, 10)).settled(content, screen, max: 5), Zoom.identity);
    expect(const Zoom(scale: 9, offset: Offset.zero).settled(content, screen, max: 5).scale, 5);
  });

  test('rubber band: past a limit the image follows with resistance', () {
    expect(rubberBand(0.5, min: 1, max: 5), inExclusiveRange(0.5, 1));
    expect(rubberBand(3, min: 1, max: 5), 3);
    expect(rubberBand(7, min: 1, max: 5), inExclusiveRange(5, 7));
  });

  test('dismiss: a long drag or a fast flick closes, a slow short one springs back', () {
    expect(shouldDismiss(offset: 300, velocity: 0, height: 800), isTrue);
    expect(shouldDismiss(offset: 40, velocity: 1400, height: 800), isTrue);
    expect(shouldDismiss(offset: 40, velocity: 100, height: 800), isFalse);
    expect(shouldDismiss(offset: 40, velocity: -1400, height: 800), isFalse, reason: 'flicked back');
  });

  test('paging settles by distance or by flick, within the gallery', () {
    expect(settlePage(position: 1.3, velocity: 0, count: 3), 1);
    expect(settlePage(position: 1.6, velocity: 0, count: 3), 2);
    expect(settlePage(position: 1.1, velocity: 900, count: 3), 2, reason: 'flick toward the next page');
    expect(settlePage(position: 1.9, velocity: -900, count: 3), 1);
    expect(settlePage(position: 2.2, velocity: 900, count: 3), 2);
  });

  test('a flight morphs the crop: cover-cropped tile to the full contained image', () {
    const tile = Rect.fromLTWH(10, 10, 100, 100);
    const full = Rect.fromLTWH(0, 300, 400, 200);
    final start = flightFrame(t: 0, aspect: 2, from: tile, to: full);
    expect(start.clip, tile);
    expect(start.image, coverRect(2, tile));
    final end = flightFrame(t: 1, aspect: 2, from: tile, to: full);
    expect(end.clip, full);
    expect(end.image, full);
  });
}
