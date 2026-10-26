import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/core/telegram/widgets/animated_sticker.dart';
import 'package:lumina/core/tdlib/td_client.dart';
import 'package:lumina/features/conversation/presentation/widgets/content/text_content.dart';
import 'package:lumina/features/conversation/presentation/widgets/message_bubble.dart';
import 'package:lumina/features/conversation/presentation/widgets/message_rows.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/widgets/animated_sticker_test.dart' show tgs;
import '../../../helpers/fakes.dart';

void main() {
  testWidgets('an emoji-only message plays its animation with no bubble around it', (tester) async {
    final m = fakeMessage(
      1,
      content: td.MessageAnimatedEmoji(
        animatedEmoji: td.AnimatedEmoji(
          sticker: tgs(),
          stickerWidth: 512,
          stickerHeight: 512,
          fitzpatrickType: 0,
          isRegularEmoji: true,
        ),
        emoji: '❤️',
      ),
    );
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: AppPreferences.inMemory()),
          RepositoryProvider(create: (_) => TelegramCache(FakeTdClient())),
          RepositoryProvider(create: (_) => FileStore(FakeTdClient())),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              row: BubbleRow(messages: [m], firstInRun: true, lastInRun: true),
              chat: fakeChat(1),
              isGroup: false,
              isChannel: false,
              animateIn: false,
              highlighted: false,
              selected: false,
              selecting: false,
              onSwipe: (_) {},
              onLongPress: () {},
              onTap: () {},
              onReplyQuoteTap: (_) {},
              onReaction: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byType(AnimatedSticker), findsOneWidget);
    final boxes = tester.widgetList<Container>(
      find.ancestor(of: find.byType(AnimatedSticker), matching: find.byType(Container)),
    );
    expect(boxes.where((c) => (c.decoration as BoxDecoration?)?.gradient != null), isEmpty);
  });

  testWidgets(
    'an emoji-only message is still until tapped; a tap plays it, a second tap asks Telegram for the effect',
    (tester) async {
      final client = FakeTdClient()
        ..respond = (f) => f is td.ClickAnimatedEmojiMessage ? tgs() : const td.Ok();
      final m = fakeMessage(
        7,
        content: td.MessageAnimatedEmoji(
          animatedEmoji: td.AnimatedEmoji(
            sticker: tgs(),
            stickerWidth: 512,
            stickerHeight: 512,
            fitzpatrickType: 0,
            isRegularEmoji: true,
          ),
          emoji: '❤️',
        ),
      );
      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider.value(value: AppPreferences.inMemory()),
            RepositoryProvider<TdClient>.value(value: client),
            RepositoryProvider(create: (_) => FileStore(client)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: BigEmojiContent(emoji: '❤️', sticker: tgs(), message: m, footer: const SizedBox()),
            ),
          ),
        ),
      );
      expect(tester.widget<AnimatedSticker>(find.byType(AnimatedSticker)).autoplay, isFalse);
      await tester.tap(find.byType(BigEmojiContent));
      await tester.pump();
      expect(tester.widget<AnimatedSticker>(find.byType(AnimatedSticker).first).autoplay, isTrue);
      expect(client.sentOf<td.ClickAnimatedEmojiMessage>(), isEmpty);
      await tester.tap(find.byType(BigEmojiContent));
      await tester.pump();
      await tester.pump();
      expect(client.sentOf<td.ClickAnimatedEmojiMessage>().single.messageId, 7);
      expect(find.byKey(const ValueKey('emoji-effect')), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
