import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/tdlib/td_client.dart';
import '../../../core/tdlib/td_errors.dart';
import '../../../core/telegram/telegram_cache.dart';

/// Chat-list level operations. Chat data itself lives in [TelegramCache].
class ChatsRepository {
  ChatsRepository({required this._client, required this._cache});

  final TdClient _client;
  final TelegramCache _cache;

  TelegramCache get cache => _cache;

  /// Asks TDLib to announce more chats of [list] through updates.
  /// Returns false once everything is loaded (TDLib answers 404).
  Future<bool> loadMore({td.ChatList list = const td.ChatListMain(), int limit = 40}) async {
    try {
      await _client.invoke<td.Ok>(td.LoadChats(chatList: list, limit: limit));
      return true;
    } on TdException catch (e) {
      if (e.code == 404) return false;
      rethrow;
    }
  }

  Future<td.Chat> chat(int chatId) async =>
      _cache.chats[chatId] ?? await _client.invoke<td.Chat>(td.GetChat(chatId: chatId));

  /// Local search first (instant), then server for public chats/users.
  Future<List<td.Chat>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    final ids = <int>{};
    final local = await _client.invoke<td.Chats>(td.SearchChats(query: query, limit: 30));
    ids.addAll(local.chatIds);
    try {
      final remote = await _client.invoke<td.Chats>(td.SearchChatsOnServer(query: query, limit: 30));
      ids.addAll(remote.chatIds);
    } on TdException {
      // Bots cannot search on the server; local results are enough.
    }
    if (query.startsWith('@') || RegExp(r'^[A-Za-z]\w{3,}$').hasMatch(query)) {
      try {
        final public = await _client.invoke<td.Chat>(
          td.SearchPublicChat(username: query.replaceFirst('@', '')),
        );
        ids.add(public.id);
      } on TdException {
        // No such username.
      }
    }
    return [for (final id in ids) ?_cache.chats[id]];
  }

  Future<td.Chat> openPrivateChat(int userId) =>
      _client.invoke<td.Chat>(td.CreatePrivateChat(userId: userId, force: false));

  Future<void> setPinned(int chatId, bool pinned, {td.ChatList list = const td.ChatListMain()}) =>
      _client.invoke<td.Ok>(td.ToggleChatIsPinned(chatList: list, chatId: chatId, isPinned: pinned));

  Future<void> setMarkedUnread(int chatId, bool unread) =>
      _client.invoke<td.Ok>(td.ToggleChatIsMarkedAsUnread(chatId: chatId, isMarkedAsUnread: unread));

  /// Reads the whole chat: its messages (viewing the last one with
  /// forceRead reads everything before it), mentions, and the manual
  /// "marked as unread" flag. An explicit action, so it ignores the
  /// "don't send read receipts" setting.
  Future<void> markRead(td.Chat chat) async {
    final last = chat.lastMessage;
    if (chat.unreadCount > 0 && last != null) {
      await _client.invoke<td.Ok>(td.ViewMessages(chatId: chat.id, messageIds: [last.id], forceRead: true));
    }
    if (chat.unreadMentionCount > 0) {
      await _client.invoke<td.Ok>(td.ReadAllChatMentions(chatId: chat.id));
    }
    if (chat.isMarkedAsUnread) await setMarkedUnread(chat.id, false);
  }

  Future<void> setMuted(int chatId, bool muted) async {
    final chat = await this.chat(chatId);
    await _client.invoke<td.Ok>(
      td.SetChatNotificationSettings(
        chatId: chatId,
        notificationSettings: chat.notificationSettings.copyWith(
          useDefaultMuteFor: false,
          muteFor: muted ? 0x7fffffff : 0,
        ),
      ),
    );
  }

  /// Leaves a group/channel, or deletes a private chat's history for self.
  Future<void> leaveOrDelete(td.Chat chat) async {
    switch (chat.type) {
      case td.ChatTypePrivate() || td.ChatTypeSecret():
        await _client.invoke<td.Ok>(
          td.DeleteChatHistory(chatId: chat.id, removeFromChatList: true, revoke: false),
        );
      default:
        await _client.invoke<td.Ok>(td.LeaveChat(chatId: chat.id));
    }
  }
}
