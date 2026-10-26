import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/conversation/presentation/widgets/send_orb.dart';

Widget orb(double charge, {OrbMode mode = OrbMode.send}) => MaterialApp(
  home: Center(
    child: SendOrb(mode: mode, charge: charge, onTap: () {}),
  ),
);

void main() {
  testWidgets('a restored draft sits still: no frames until the text changes', (tester) async {
    await tester.pumpWidget(orb(0.5));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('typing animates the orb, then it settles shortly after', (tester) async {
    await tester.pumpWidget(orb(0.5));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(orb(0.6));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('recording keeps pulsing', (tester) async {
    await tester.pumpWidget(orb(0, mode: OrbMode.stop));
    await tester.pump(const Duration(seconds: 3));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
