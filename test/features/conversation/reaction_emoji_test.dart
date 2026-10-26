import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/conversation/bloc/conversation_cubit.dart';
import 'package:lumina/features/conversation/data/messages_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

td.AvailableReactions available(List<String> emoji) => td.AvailableReactions(
  topReactions: [
    for (final e in emoji) td.AvailableReaction(type: td.ReactionTypeEmoji(emoji: e), needsPremium: false),
  ],
  recentReactions: const [],
  popularReactions: const [],
  allowCustomEmoji: false,
  areTags: false,
);

void main() {
  ConversationCubit cubit(FakeTdClient client) => ConversationCubit(
    chatId: 1,
    repository: MessagesRepository(client: client, prefs: AppPreferences.inMemory()),
    cache: TelegramCache.detached()..apply(td.UpdateNewChat(chat: fakeChat(1))),
    updates: client.updates,
  );

  test('a red heart with the emoji variation selector reacts as Telegram\'s plain ❤', () async {
    final client = FakeTdClient()
      ..respond = (f) => f is td.GetMessageAvailableReactions ? available(['👍', '❤']) : const td.Ok();
    final c = cubit(client);
    expect(await c.toggleReaction(fakeMessage(5), '❤️'), isTrue);
    final sent = client.sentOf<td.AddMessageReaction>().single;
    expect((sent.reactionType as td.ReactionTypeEmoji).emoji, '❤');
    await c.close();
  });

  test('a reaction the chat does not allow is refused, not sent', () async {
    final client = FakeTdClient()
      ..respond = (f) => f is td.GetMessageAvailableReactions ? available(['👍']) : const td.Ok();
    final c = cubit(client);
    expect(await c.toggleReaction(fakeMessage(5), '🔥'), isFalse);
    expect(client.sentOf<td.AddMessageReaction>(), isEmpty);
    await c.close();
  });
}
