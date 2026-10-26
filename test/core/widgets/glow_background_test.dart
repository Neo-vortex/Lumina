import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/widgets/glow_background.dart';

void main() {
  testWidgets('a content screen backdrop is still: no frames once drawn', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GlowBackground(child: SizedBox())));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('drift keeps the orbs moving where asked (login, calls)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GlowBackground(drift: true, child: SizedBox())));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
  });
}
