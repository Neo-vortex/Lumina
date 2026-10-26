import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/conversation/presentation/widgets/message_details_sheet.dart';

import '../../../helpers/fakes.dart';

void main() {
  testWidgets('details show the message id and the exact time to the second', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final sent = DateTime(2026, 10, 26, 14, 2, 37);
    final m = fakeMessage(
      123456,
      date: sent.millisecondsSinceEpoch ~/ 1000,
    ).copyWith(editDate: DateTime(2026, 10, 26, 14, 5, 9).millisecondsSinceEpoch ~/ 1000);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMessageDetails(context, m, readStatus: Future.value('Read today at 14:10')),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('123456'), findsOneWidget);
    expect(find.text('2026-10-26 14:02:37'), findsOneWidget);
    expect(find.text('2026-10-26 14:05:09'), findsOneWidget);
    expect(find.text('Read today at 14:10'), findsOneWidget);
  });
}
