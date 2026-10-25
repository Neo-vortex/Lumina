import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:lumina/core/telegram/entity_edit.dart';
import 'package:lumina/core/telegram/widgets/formatted_text_view.dart';
import 'package:lumina/features/conversation/presentation/widgets/formatting_controller.dart';

td.TextEntity e(int o, int l, [td.TextEntityType t = const td.TextEntityTypeBold()]) =>
    td.TextEntity(offset: o, length: l, type: t);

void main() {
  group('EntityEdit.afterEdit', () {
    test('typing before an entity shifts it; typing at its end extends it', () {
      // "hello world", bold "world" [6,11)
      expect(EntityEdit.afterEdit('hello world', 'hello big world', [e(6, 5)]).single.offset, 10);
      final grown = EntityEdit.afterEdit('hello world', 'hello world!', [e(6, 5)]).single;
      expect((grown.offset, grown.length), (6, 6));
    });

    test('deleting inside shrinks, deleting everything removes', () {
      final s = EntityEdit.afterEdit('hello world', 'hello wd', [e(6, 5)]).single;
      expect((s.offset, s.length), (6, 2));
      expect(EntityEdit.afterEdit('hello world', 'hello ', [e(6, 5)]), isEmpty);
    });
  });

  test('trim moves entities with leading whitespace', () {
    final f = EntityEdit.trim('  hi there  ', [e(5, 5)]);
    expect(f.text, 'hi there');
    expect((f.entities.single.offset, f.entities.single.length), (3, 5));
  });

  group('toggle', () {
    test('applies, merges touching runs and removes when fully covered', () {
      var es = EntityEdit.toggle(const [], 0, 3, const td.TextEntityTypeBold());
      es = EntityEdit.toggle(es, 3, 6, const td.TextEntityTypeBold());
      expect((es.single.offset, es.single.length), (0, 6));
      es = EntityEdit.toggle(es, 2, 4, const td.TextEntityTypeBold());
      expect([for (final x in es) (x.offset, x.length)], [(0, 2), (4, 2)]);
    });

    test('code block replaces a quote on the same text', () {
      final es = EntityEdit.toggle(
        [e(0, 5, const td.TextEntityTypeBlockQuote())],
        0,
        5,
        const td.TextEntityTypePre(),
      );
      expect(es.single.type, isA<td.TextEntityTypePre>());
    });
  });

  test('FormattingController keeps formatting through edits', () {
    final c = FormattingController(text: 'make this bold');
    c.selection = const TextSelection(baseOffset: 10, extentOffset: 14);
    c.toggle(const td.TextEntityTypeBold());
    expect(c.isApplied(const td.TextEntityTypeBold()), isTrue);
    c.value = const TextEditingValue(text: 'please make this bold');
    expect((c.entities.single.offset, c.entities.single.length), (17, 4));
    c.clear();
    expect(c.entities, isEmpty);
  });

  testWidgets('code blocks and quotes render as blocks', (tester) async {
    const text = td.FormattedText(
      text: 'Intro\nprint(1)\nA wise quote',
      entities: [
        td.TextEntity(offset: 6, length: 8, type: td.TextEntityTypePreCode(language: 'python')),
        td.TextEntity(offset: 15, length: 12, type: td.TextEntityTypeExpandableBlockQuote()),
      ],
    );
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: FormattedTextView(text))));
    expect(find.text('python'), findsOneWidget);
    expect(find.text('print(1)'), findsOneWidget);
    expect(find.byTooltip('Copy code'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    await tester.pump();
    expect(find.byIcon(Icons.expand_less_rounded), findsOneWidget);
  });
}
