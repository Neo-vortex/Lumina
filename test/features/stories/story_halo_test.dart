import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/stories/presentation/widgets/story_halo.dart';

void main() {
  testWidgets('an unseen halo spins on arrival, then rests', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StoryHalo(size: 50, unseen: true, child: SizedBox())));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced motion: never spins', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: StoryHalo(size: 50, unseen: true, child: SizedBox())),
      ),
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
