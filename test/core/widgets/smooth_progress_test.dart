import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/widgets/smooth_progress.dart';

void main() {
  Future<List<double?>> seen(WidgetTester tester, double? value, {int frames = 1}) async {
    final out = <double?>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SmoothProgress(
          value: value,
          builder: (context, v) {
            out.add(v);
            return const SizedBox();
          },
        ),
      ),
    );
    for (var i = 1; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return out;
  }

  testWidgets('the first value shows as is', (tester) async {
    expect((await seen(tester, 0.4)).single, 0.4);
  });

  testWidgets('a jump glides there through in-between values, never past it', (tester) async {
    await seen(tester, 0.1);
    final path = await seen(tester, 0.9, frames: 12);
    expect(path.first, closeTo(0.1, 0.001), reason: 'starts where it was');
    expect(path.last, closeTo(0.9, 0.001), reason: 'lands on the real value');
    for (var i = 1; i < path.length; i++) {
      expect(path[i]!, greaterThanOrEqualTo(path[i - 1]!));
      expect(path[i]!, lessThanOrEqualTo(0.9));
    }
    expect(path.where((v) => v! > 0.15 && v < 0.85), isNotEmpty);
  });

  testWidgets('a new target mid-glide continues from where the bar is', (tester) async {
    await seen(tester, 0.0);
    final first = await seen(tester, 0.5, frames: 3);
    final second = await seen(tester, 1.0, frames: 2);
    expect(second.first, closeTo(first.last!, 0.001));
  });

  testWidgets('indeterminate stays indeterminate', (tester) async {
    expect((await seen(tester, null)).single, isNull);
  });
}
