import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/voice/presentation/widgets/live_waveform.dart';

void main() {
  test('bar heights follow the absolute level, not a per-window rescale (no jumping)', () {
    // A quiet stretch stays small even when nothing louder is on screen.
    expect(waveBarHeight(0.1, 28), lessThan(28 * 0.35));
    expect(waveBarHeight(1, 28), closeTo(28, 0.01));
    expect(waveBarHeight(0, 28), greaterThan(0), reason: 'a floor so silence still shows a line');
  });

  test('the newest bar eases toward its level instead of snapping', () {
    final eased = easeLevel(current: 0.2, target: 0.9, dtMs: 16);
    expect(eased, greaterThan(0.2));
    expect(eased, lessThan(0.9));
  });

  testWidgets('it animates smoothly between samples (frames keep coming while recording)', (tester) async {
    final levels = [0.2, 0.5];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveWaveform(levels: () => levels, color: Colors.red),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
