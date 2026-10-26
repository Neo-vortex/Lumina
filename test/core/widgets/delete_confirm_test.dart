import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/widgets/delete_confirm.dart';

void main() {
  Future<Future<bool?>> show(WidgetTester tester, {required bool canForEveryone}) async {
    late Future<bool?> result;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = confirmDeleteMessages(
              context,
              count: 1,
              canForEveryone: canForEveryone,
              otherName: 'Ada',
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    return result;
  }

  testWidgets('offers "also delete for Ada" when allowed; toggling it deletes for both', (tester) async {
    final result = await show(tester, canForEveryone: true);
    expect(find.text('Delete this message?'), findsOneWidget);
    await tester.tap(find.text('Also delete for Ada'));
    await tester.pump();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(await result, isTrue);
  });

  testWidgets('no toggle when only self-delete is allowed; cancel returns null', (tester) async {
    final result = await show(tester, canForEveryone: false);
    expect(find.textContaining('Also delete'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(await result, isNull);
  });
}
