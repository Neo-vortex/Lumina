import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/chats/bloc/chat_list_cubit.dart';
import 'package:lumina/features/chats/data/chats_repository.dart';

import '../../helpers/fakes.dart';

void main() {
  test('the proxy sponsor channel is listed and labelled, or hidden when the setting is on', () async {
    final cache = TelegramCache.detached()
      ..apply(td.UpdateNewChat(chat: fakeChat(1, order: 10)))
      ..apply(
        td.UpdateNewChat(
          chat: fakeChat(2).copyWith(
            positions: const [
              td.ChatPosition(
                list: td.ChatListMain(),
                order: 99,
                isPinned: false,
                source: td.ChatSourceMtprotoProxy(),
              ),
            ],
          ),
        ),
      );
    final prefs = AppPreferences.inMemory();
    final cubit = ChatListCubit(
      repository: ChatsRepository(client: FakeTdClient(), cache: cache),
      prefs: prefs,
    );
    await cubit.start();
    expect(cubit.state.chats.map((c) => c.id), [2, 1]);
    expect(cache.isProxySponsored(cache.chats[2]!), isTrue);
    expect(cache.isProxySponsored(cache.chats[1]!), isFalse);

    prefs.hideProxySponsor = true;
    expect(cubit.state.chats.map((c) => c.id), [1]);
    await cubit.close();
  });
}
