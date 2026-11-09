import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumina/features/conversation/presentation/widgets/reaction_panel.dart';

class _Catalog implements ReactionCatalog {
  @override
  Future<({List<String> recent, List<String> popular})> sections() async =>
      (recent: ['🔥'], popular: ['👍', '❤️']);

  @override
  Future<List<({String name, List<String> emojis})>> categories() async => [
    (name: 'Love', emojis: ['❤️', '😍', '🥰']), // 🥰 isn't allowed in this chat
    (name: 'Premium only', emojis: ['🦄']),
  ];

  @override
  Future<List<String>> search(String query) async => query == 'fire' ? ['🔥', '🧯'] : [];
}

void main() {
  // The chat's spelling: a plain heart without the variation selector.
  const available = ['👍', '❤', '🔥', '😍', '😢'];

  Future<List<String>> pump(WidgetTester tester, List<String> picked) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReactionPanel(
            available: available,
            catalog: _Catalog(),
            onPick: picked.add,
            icon: (e, size) => Text(e, style: TextStyle(fontSize: size * 0.8)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('sections, then the rest; only categories with allowed reactions', (tester) async {
    final picked = await pump(tester, []);
    expect(find.text('RECENT'), findsOneWidget);
    expect(find.text('POPULAR'), findsOneWidget);
    expect(find.text('MORE REACTIONS'), findsOneWidget);
    expect(find.text('Love'), findsOneWidget);
    expect(find.text('Premium only'), findsNothing);
    await tester.tap(find.text('😢'));
    expect(picked, ['😢']);
  });

  testWidgets('a category narrows the grid, in the chat spelling', (tester) async {
    final picked = await pump(tester, []);
    await tester.tap(find.text('Love'));
    await tester.pumpAndSettle();
    expect(find.text('LOVE'), findsOneWidget);
    expect(find.text('🥰'), findsNothing);
    expect(find.text('😢'), findsNothing);
    await tester.tap(find.text('❤').last);
    expect(picked, ['❤']);
  });

  testWidgets('search shows matching allowed reactions, or says none match', (tester) async {
    await pump(tester, []);
    await tester.enterText(find.byType(TextField), 'fire');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('RESULTS'), findsOneWidget);
    expect(find.text('🔥'), findsOneWidget);
    expect(find.text('🧯'), findsNothing);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('No reactions match'), findsOneWidget);
  });
}
