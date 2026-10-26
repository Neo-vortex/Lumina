import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/conversation/bloc/conversation_cubit.dart';
import 'package:lumina/features/conversation/data/messages_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

void main() {
  test('only status changes of users the chat shows re-emit', () async {
    final client = FakeTdClient();
    final cache = TelegramCache.detached()
      ..apply(td.UpdateNewChat(chat: fakeChat(1)))
      ..apply(td.UpdateUser(user: fakeUser().copyWith(id: 1)))
      ..apply(td.UpdateUser(user: fakeUser().copyWith(id: 999)));
    final cubit = ConversationCubit(
      chatId: 1,
      repository: MessagesRepository(client: client, prefs: AppPreferences.inMemory()),
      cache: cache,
      updates: client.updates,
    );
    final emitted = <int>[];
    final sub = cubit.stream.listen((s) => emitted.add(s.revision));

    cache.apply(const td.UpdateUserStatus(userId: 999, status: td.UserStatusOnline(expires: 1)));
    await Future<void>.delayed(Duration.zero);
    expect(emitted, isEmpty, reason: 'a stranger going online must not rebuild the chat');

    cache.apply(const td.UpdateUserStatus(userId: 1, status: td.UserStatusOnline(expires: 1)));
    await Future<void>.delayed(Duration.zero);
    expect(emitted, hasLength(1), reason: 'the peer going online updates the header');

    await sub.cancel();
    await cubit.close();
  });

  test('a burst of view-count updates is coalesced into one emit with the latest counts', () async {
    final client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetChatHistory(fromMessageId: 0) => td.Messages(
          totalCount: 2,
          messages: [fakeMessage(2), fakeMessage(1)],
        ),
        td.GetChatHistory() => const td.Messages(totalCount: 0, messages: []),
        td.GetChatPinnedMessage() => const td.TdError(code: 404, message: 'Not Found'),
        _ => const td.Ok(),
      };
    final cache = TelegramCache.detached()..apply(td.UpdateNewChat(chat: fakeChat(1)));
    final cubit = ConversationCubit(
      chatId: 1,
      repository: MessagesRepository(client: client, prefs: AppPreferences.inMemory()),
      cache: cache,
      updates: client.updates,
    );
    await cubit.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final emitted = <List<td.Message>>[];
    final sub = cubit.stream.listen((s) => emitted.add(s.messages));

    for (var views = 1; views <= 10; views++) {
      client.emitUpdate(
        td.UpdateMessageInteractionInfo(
          chatId: 1,
          messageId: 2,
          interactionInfo: td.MessageInteractionInfo(viewCount: views, forwardCount: 0),
        ),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(emitted, hasLength(1));
    expect(emitted.single.first.interactionInfo?.viewCount, 10);

    await sub.cancel();
    await cubit.close();
  });
}
