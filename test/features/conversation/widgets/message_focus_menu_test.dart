import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/features/conversation/presentation/widgets/message_menu.dart';

import '../../../helpers/fakes.dart';

void main() {
  Future<Future<({MessageAction? action, String? reaction})?>> open(WidgetTester tester) async {
    late Future<({MessageAction? action, String? reaction})?> result;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: AppPreferences.inMemory()),
          RepositoryProvider(create: (_) => FileStore(FakeTdClient())),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => result = showMessageMenu(
                context,
                message: fakeMessage(1, outgoing: true),
                properties: null,
                reactions: Future.value(['❤️', '👍', '🔥', '😂', '😮', '🎉', '🙏']),
                quickReactions: const ['🔥', '❤️', '👍', '😂', '😮'],
                protectedContent: false,
                anchor: const Rect.fromLTWH(100, 400, 200, 48),
                bubble: const Text('the bubble'),
                readStatus: Future.value('Read today at 14:02'),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    return result;
  }

  testWidgets('focus menu: quick reactions first, read status, lifted bubble, actions', (tester) async {
    await open(tester);
    expect(find.text('the bubble'), findsOneWidget);
    expect(find.text('Read today at 14:02'), findsOneWidget);
    expect(find.text('Reply'), findsOneWidget);
    // Quick reactions in the chosen order; others wait behind the expander.
    final pill = find.byKey(const ValueKey('quick-reactions'));
    expect(find.descendant(of: pill, matching: find.text('🔥')), findsOneWidget);
    expect(find.text('🎉'), findsNothing);
    await tester.tap(find.byTooltip('More reactions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('🎉'), findsOneWidget);
  });

  testWidgets('tapping a reaction or an action returns it', (tester) async {
    final result = await open(tester);
    await tester.tap(find.text('🔥'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect((await result)?.reaction, '🔥');
  });
}
