import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/conversation/presentation/widgets/content/rich_cards_content.dart';

void main() {
  testWidgets('a live location pulses a few times, then rests', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LivePulse(active: true, child: SizedBox())));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced motion: no pulse', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: LivePulse(active: true, child: SizedBox())),
      ),
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
