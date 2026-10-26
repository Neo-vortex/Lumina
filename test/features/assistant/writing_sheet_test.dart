import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/assistant/data/action_extractor.dart';
import 'package:lumina/features/assistant/domain/writing_tool.dart';
import 'package:lumina/features/assistant/presentation/writing_sheet.dart';

void main() {
  Future<List<String?>> open(WidgetTester tester, WritingFn write) async {
    final result = <String?>[];
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showWritingTools(context, text: 'i will came at 8', write: write).then(result.add),
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

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('pick a tool, see before and after, replace', (tester) async {
    final used = <WritingTool>[];
    final result = await open(tester, (text, tool, onStage) async {
      used.add(tool);
      return 'I will come at 8.';
    });
    await tester.tap(find.text('Fix grammar'));
    await settle(tester);
    expect(find.text('i will came at 8'), findsOneWidget);
    expect(find.text('I will come at 8.'), findsOneWidget);
    await tester.tap(find.text('Replace'));
    await settle(tester);
    expect(result, ['I will come at 8.']);
    expect(used, [WritingTool.grammar]);
  });

  testWidgets('a failure says so and offers Try again', (tester) async {
    var calls = 0;
    await open(tester, (text, tool, onStage) async {
      calls++;
      if (calls == 1) throw TimeoutException('slow');
      return 'Better.';
    });
    await tester.tap(find.text('Rewrite'));
    await settle(tester);
    expect(find.textContaining('took too long'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.text('Better.'), findsOneWidget);
  });

  test('stages read as words', () {
    expect(ExtractStage.values, hasLength(3));
  });
}
