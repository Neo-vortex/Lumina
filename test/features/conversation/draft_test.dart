import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/conversation/bloc/conversation_cubit.dart';
import 'package:lumina/features/conversation/data/messages_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

void main() {
  ConversationCubit cubitFor(FakeTdClient client, TelegramCache cache) => ConversationCubit(
    chatId: 1,
    repository: MessagesRepository(client: client, prefs: AppPreferences.inMemory()),
    cache: cache,
    updates: client.updates,
  );

  test('no draft is saved in a channel the account cannot post in', () async {
    final client = FakeTdClient();
    final cache = TelegramCache.detached()
      ..apply(td.UpdateSupergroup(supergroup: fakeSupergroup(7, isChannel: true)))
      ..apply(
        td.UpdateNewChat(
          chat: fakeChat(1).copyWith(type: const td.ChatTypeSupergroup(supergroupId: 7, isChannel: true)),
        ),
      );
    final cubit = cubitFor(client, cache);
    await cubit.saveDraft('');
    expect(client.sentOf<td.SetChatDraftMessage>(), isEmpty);
    await cubit.close();
  });

  test('drafts are still saved where the account can post', () async {
    final client = FakeTdClient();
    final cache = TelegramCache.detached()..apply(td.UpdateNewChat(chat: fakeChat(1)));
    final cubit = cubitFor(client, cache);
    await cubit.saveDraft('hello');
    expect(client.sentOf<td.SetChatDraftMessage>(), hasLength(1));
    await cubit.close();
  });
}
