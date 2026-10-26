import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/chats/data/chats_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

void main() {
  test('mark as read reads the messages, not just the manual unread mark', () async {
    final client = FakeTdClient();
    final repo = ChatsRepository(client: client, cache: TelegramCache.detached());
    final chat = fakeChat(
      1,
      unread: 4,
      lastMessage: fakeMessage(90),
    ).copyWith(isMarkedAsUnread: true, unreadMentionCount: 1);
    await repo.markRead(chat);
    final view = client.sentOf<td.ViewMessages>().single;
    expect(view.chatId, 1);
    expect(view.messageIds, [90]);
    expect(view.forceRead, isTrue);
    expect(client.sentOf<td.ToggleChatIsMarkedAsUnread>().single.isMarkedAsUnread, isFalse);
    expect(client.sentOf<td.ReadAllChatMentions>(), hasLength(1));
  });

  test('a chat only marked unread just clears the mark', () async {
    final client = FakeTdClient();
    final repo = ChatsRepository(client: client, cache: TelegramCache.detached());
    await repo.markRead(fakeChat(1, lastMessage: fakeMessage(90)).copyWith(isMarkedAsUnread: true));
    expect(client.sentOf<td.ViewMessages>(), isEmpty);
    expect(client.sentOf<td.ToggleChatIsMarkedAsUnread>(), hasLength(1));
  });
}
