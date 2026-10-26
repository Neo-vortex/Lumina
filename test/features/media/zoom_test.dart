import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/media/presentation/screens/media_viewer_screen.dart';

void main() {
  test('double-tap zoom keeps the tapped point under the finger', () {
    const p = Offset(120, 300);
    final m = zoomAt(p, 2.5);
    expect(MatrixUtils.transformPoint(m, p), offsetMoreOrLessEquals(p));
    expect(m.getMaxScaleOnAxis(), 2.5);
  });

  testWidgets('the zoom animates instead of jumping', (tester) async {
    final zoom = TransformationController();
    await tester.pumpWidget(
      MaterialApp(
        home: DoubleTapZoom(
          controller: zoom,
          child: const ColoredBox(color: Colors.black, child: SizedBox.expand()),
        ),
      ),
    );
    await tester.tap(find.byType(DoubleTapZoom));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(DoubleTapZoom));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final mid = zoom.value.getMaxScaleOnAxis();
    expect(mid, greaterThan(1.05));
    expect(mid, lessThan(2.45));
    await tester.pump(const Duration(milliseconds: 400));
    expect(zoom.value.getMaxScaleOnAxis(), closeTo(2.5, 0.01));
  });
}
