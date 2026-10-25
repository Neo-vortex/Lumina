import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:lumina/core/telegram/telegram_cache.dart';

import '../../helpers/fakes.dart';

void main() {
  late TelegramCache cache;
  setUp(() => cache = TelegramCache.detached());

  List<int> mainIds() => cache.chatsIn(const td.ChatListMain()).map((c) => c.id).toList();

  test('orders the main list by position order, newest first', () {
    cache
      ..apply(td.UpdateNewChat(chat: fakeChat(1, order: 10)))
      ..apply(td.UpdateNewChat(chat: fakeChat(2, order: 30)))
      ..apply(td.UpdateNewChat(chat: fakeChat(3, order: 20)));
    expect(mainIds(), [2, 3, 1]);
  });

  test('a position update moves a chat; order 0 removes it from the list', () {
    cache
      ..apply(td.UpdateNewChat(chat: fakeChat(1, order: 10)))
      ..apply(td.UpdateNewChat(chat: fakeChat(2, order: 20)));
    cache.apply(
      const td.UpdateChatPosition(
        chatId: 1,
        position: td.ChatPosition(list: td.ChatListMain(), order: 99, isPinned: true),
      ),
    );
    expect(mainIds(), [1, 2]);
    cache.apply(
      const td.UpdateChatPosition(
        chatId: 2,
        position: td.ChatPosition(list: td.ChatListMain(), order: 0, isPinned: false),
      ),
    );
    expect(mainIds(), [1]);
  });

  test('read and unread updates patch the cached chat and emit events', () async {
    cache.apply(td.UpdateNewChat(chat: fakeChat(1, order: 10, unread: 3)));
    final events = <CacheEvent>[];
    cache.events.listen(events.add);
    cache.apply(const td.UpdateChatReadInbox(chatId: 1, lastReadInboxMessageId: 50, unreadCount: 0));
    cache.apply(const td.UpdateChatReadOutbox(chatId: 1, lastReadOutboxMessageId: 40));
    expect(cache.chats[1]!.unreadCount, 0);
    expect(cache.chats[1]!.lastReadOutboxMessageId, 40);
    expect(events.whereType<ChatChanged>(), hasLength(2));
  });

  test('last message can be cleared (copyWith cannot null fields)', () {
    cache.apply(td.UpdateNewChat(chat: fakeChat(1, order: 10, lastMessage: fakeMessage(5))));
    cache.apply(const td.UpdateChatLastMessage(chatId: 1, positions: []));
    expect(cache.chats[1]!.lastMessage, isNull);
  });

  test('typing actions appear and are cancelled', () {
    cache.apply(td.UpdateNewChat(chat: fakeChat(1, order: 10)));
    cache.apply(
      const td.UpdateChatAction(
        chatId: 1,
        senderId: td.MessageSenderUser(userId: 7),
        action: td.ChatActionTyping(),
      ),
    );
    expect(cache.actionsIn(1), hasLength(1));
    cache.apply(
      const td.UpdateChatAction(
        chatId: 1,
        senderId: td.MessageSenderUser(userId: 7),
        action: td.ChatActionCancel(),
      ),
    );
    expect(cache.actionsIn(1), isEmpty);
  });

  test('closing the session clears everything', () {
    cache.apply(td.UpdateNewChat(chat: fakeChat(1, order: 10)));
    cache.apply(const td.UpdateAuthorizationState(authorizationState: td.AuthorizationStateClosed()));
    expect(cache.chats, isEmpty);
  });
}
