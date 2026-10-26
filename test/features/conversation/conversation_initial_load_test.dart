import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/conversation/bloc/conversation_cubit.dart';
import 'package:lumina/features/conversation/data/messages_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

void main() {
  test('a chat TDLib only knows the last message of keeps loading until the page is full', () async {
    // TDLib's first answers come from its local cache (just the last message);
    // older ones arrive when asked again from that message.
    final client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetChatHistory(fromMessageId: 0) => td.Messages(totalCount: 1, messages: [fakeMessage(100)]),
        td.GetChatHistory(:final fromMessageId) when fromMessageId > 80 => td.Messages(
          totalCount: 20,
          messages: [for (var id = fromMessageId - 1; id > fromMessageId - 21; id--) fakeMessage(id)],
        ),
        td.GetChatHistory() => const td.Messages(totalCount: 0, messages: []),
        td.OpenChat() => const td.Ok(),
        _ => const td.TdError(code: 404, message: 'Not Found'),
      };
    final cache = TelegramCache.detached()..apply(td.UpdateNewChat(chat: fakeChat(1, order: 5)));
    final cubit = ConversationCubit(
      chatId: 1,
      repository: MessagesRepository(client: client, prefs: AppPreferences.inMemory()),
      cache: cache,
      updates: client.updates,
    );
    await cubit.start();
    expect(cubit.state.initialLoading, isFalse);
    expect(cubit.state.messages.length, greaterThan(1));
    expect(cubit.state.messages.first.id, 100);
    await cubit.close();
  });

  test('a short chat stops asking and drops the loading row', () async {
    final client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetChatHistory(fromMessageId: 0) => td.Messages(
          totalCount: 2,
          messages: [fakeMessage(2), fakeMessage(1)],
        ),
        td.GetChatHistory() => const td.Messages(totalCount: 0, messages: []),
        td.OpenChat() => const td.Ok(),
        _ => const td.TdError(code: 404, message: 'Not Found'),
      };
    final cache = TelegramCache.detached()..apply(td.UpdateNewChat(chat: fakeChat(1, order: 5)));
    final cubit = ConversationCubit(
      chatId: 1,
      repository: MessagesRepository(client: client, prefs: AppPreferences.inMemory()),
      cache: cache,
      updates: client.updates,
    );
    await cubit.start();
    expect(cubit.state.messages.map((m) => m.id), [2, 1]);
    expect(cubit.state.hasOlder, isFalse, reason: 'no spinner row left behind');
    await cubit.close();
  });
}
