import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/conversation/presentation/widgets/composer.dart';

import '../../../helpers/fakes.dart';

void main() {
  testWidgets(
    'the smiley swaps in the media panel; emoji insert at the cursor; tapping the field closes it',
    (tester) async {
      final text = TextEditingController(text: 'hi ');
      ValueChanged<String>? insert;
      await tester.pumpWidget(
        RepositoryProvider(
          create: (_) => TelegramCache(FakeTdClient()),
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: Composer(
                  controller: text,
                  replyTo: null,
                  editing: null,
                  onSend: (_, _, _) async {},
                  onCancelMode: () {},
                  onChanged: (_) {},
                  mediaPanel: (height, onEmoji, onSent) {
                    insert = onEmoji;
                    return SizedBox(key: const ValueKey('panel'), height: height);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('panel')), findsNothing);
      await tester.tap(find.byTooltip('Emoji, stickers and GIFs'));
      await tester.pump();
      expect(find.byKey(const ValueKey('panel')), findsOneWidget);

      text.selection = const TextSelection.collapsed(offset: 3);
      insert!('😀');
      expect(text.text, 'hi 😀');

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(find.byKey(const ValueKey('panel')), findsNothing);
      await tester.pump(const Duration(seconds: 2));
    },
  );
}
