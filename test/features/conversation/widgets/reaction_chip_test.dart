import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/conversation/presentation/widgets/reactions_row.dart';

void main() {
  Future<void> chip(WidgetTester tester, {required bool pending, int count = 3}) => tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: Center(
          child: ReactionChip(
            emoji: '❤',
            count: count,
            chosen: false,
            pending: pending,
            burst: null,
            onTap: () {},
          ),
        ),
      ),
    ),
  );

  int shadows(WidgetTester tester) =>
      (tester
                  .widget<Container>(
                    find.descendant(of: find.byType(ReactionChip), matching: find.byType(Container)).first,
                  )
                  .decoration!
              as BoxDecoration)
          .boxShadow!
          .length;

  testWidgets('glows while TDLib works, settles when it answers, count unchanged until then', (tester) async {
    await chip(tester, pending: false);
    expect(shadows(tester), 0);
    await chip(tester, pending: true);
    await tester.pump(const Duration(milliseconds: 350));
    expect(shadows(tester), greaterThan(0), reason: 'glowing');
    expect(find.text('3'), findsOneWidget);
    await chip(tester, pending: false, count: 4);
    await tester.pump(const Duration(milliseconds: 400));
    expect(shadows(tester), 0, reason: 'glow faded with the answer');
    expect(find.text('4'), findsOneWidget);
  });
}
