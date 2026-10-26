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

  test('isMuted follows the chat-type default unless the chat overrides it', () {
    final chat = fakeChat(1, order: 10);
    cache.apply(td.UpdateNewChat(chat: chat));
    expect(cache.isMuted(cache.chats[1]!), isFalse);

    final events = <CacheEvent>[];
    cache.events.listen(events.add);
    cache.apply(
      const td.UpdateScopeNotificationSettings(
        scope: td.NotificationSettingsScopePrivateChats(),
        notificationSettings: td.ScopeNotificationSettings(
          muteFor: 0x7fffffff,
          soundId: 0,
          showPreview: true,
          useDefaultMuteStories: true,
          muteStories: false,
          storySoundId: 0,
          showStoryPoster: false,
          disablePinnedMessageNotifications: false,
          disableMentionNotifications: false,
        ),
      ),
    );
    expect(cache.isMuted(cache.chats[1]!), isTrue);
    expect(events.whereType<ChatChanged>().map((e) => e.chatId), [1]);

    cache.apply(
      td.UpdateChatNotificationSettings(
        chatId: 1,
        notificationSettings: chat.notificationSettings.copyWith(useDefaultMuteFor: false, muteFor: 0),
      ),
    );
    expect(cache.isMuted(cache.chats[1]!), isFalse);
  });

  td.ChatFolderInfo folderInfo(int id, String name) => td.ChatFolderInfo(
    id: id,
    name: td.ChatFolderName(
      text: td.FormattedText(text: name, entities: const []),
      animateCustomEmoji: false,
    ),
    icon: const td.ChatFolderIcon(name: 'Custom'),
    colorId: -1,
    isShareable: false,
    hasMyInviteLinks: false,
  );

  test('mirrors chat folders and emits FoldersChanged', () {
    final events = <CacheEvent>[];
    cache.events.listen(events.add);
    cache.apply(
      td.UpdateChatFolders(
        chatFolders: [folderInfo(3, 'Work'), folderInfo(5, 'Home')],
        mainChatListPosition: 1,
        areTagsEnabled: true,
      ),
    );
    expect(cache.chatFolders.map((f) => f.id), [3, 5]);
    expect(cache.mainListPosition, 1);
    expect(cache.folderTagsEnabled, isTrue);
    expect(events.whereType<FoldersChanged>(), hasLength(1));
  });

  test('unread counts are kept per chat list', () {
    final events = <CacheEvent>[];
    cache.events.listen(events.add);
    cache.apply(
      const td.UpdateUnreadChatCount(
        chatList: td.ChatListFolder(chatFolderId: 3),
        totalCount: 10,
        unreadCount: 4,
        unreadUnmutedCount: 2,
        markedAsUnreadCount: 0,
        markedAsUnreadUnmutedCount: 0,
      ),
    );
    expect(cache.unreadIn(const td.ChatListFolder(chatFolderId: 3)), (chats: 4, unmuted: 2));
    expect(cache.unreadIn(const td.ChatListMain()), (chats: 0, unmuted: 0));
    expect(events.whereType<UnreadCountChanged>().single.list, isA<td.ChatListFolder>());
  });

  test('foldersOf lists the folders a chat is positioned in', () {
    cache.apply(
      td.UpdateNewChat(
        chat: fakeChat(1).copyWith(
          positions: const [
            td.ChatPosition(list: td.ChatListMain(), order: 9, isPinned: false),
            td.ChatPosition(list: td.ChatListFolder(chatFolderId: 3), order: 9, isPinned: false),
            td.ChatPosition(list: td.ChatListFolder(chatFolderId: 5), order: 9, isPinned: true),
          ],
        ),
      ),
    );
    expect(cache.foldersOf(cache.chats[1]!), [3, 5]);
  });

  test('clear forgets folders and counts', () {
    cache.apply(
      td.UpdateChatFolders(
        chatFolders: [folderInfo(3, 'Work')],
        mainChatListPosition: 0,
        areTagsEnabled: false,
      ),
    );
    cache.clear();
    expect(cache.chatFolders, isEmpty);
  });
}
