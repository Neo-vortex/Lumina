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
}
