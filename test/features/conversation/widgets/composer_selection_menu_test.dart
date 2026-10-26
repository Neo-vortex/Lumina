import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/conversation/presentation/widgets/composer_selection_menu.dart';
import 'package:lumina/features/conversation/presentation/widgets/formatting_controller.dart';
import 'package:lumina_tdlib/api.dart' as td;

void main() {
  Future<FormattingController> pump(WidgetTester tester) async {
    final c = FormattingController(text: 'hello world');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TextField(
              controller: c,
              contextMenuBuilder: (context, state) => ComposerSelectionMenu(state: state, controller: c),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('selection shows the glow pill: clipboard icons and every format, no stock overflow', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(ComposerSelectionMenu), findsOneWidget);
    expect(find.byTooltip('Copy'), findsOneWidget);
    expect(find.byTooltip('Cut'), findsOneWidget);
    expect(find.byTooltip('Select all'), findsOneWidget);
    for (final f in ['Bold', 'Italic', 'Underline', 'Strikethrough', 'Spoiler', 'Monospace', 'Link']) {
      expect(find.byTooltip(f), findsOneWidget, reason: f);
    }
    expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('a format chip applies to the selection', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();
    expect(c.isApplied(const td.TextEntityTypeBold()), isTrue);
  });
}
