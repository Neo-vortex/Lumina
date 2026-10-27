import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/telegram_cache.dart';

/// What the folder gesture picker shows for a highlighted folder.
class FolderPreview {
  const FolderPreview({required this.unreadMessages, required this.unreadChats, required this.chats});

  final int unreadMessages;
  final int unreadChats;
  final List<td.Chat> chats;

  static FolderPreview of(TelegramCache cache, td.ChatList list, {int limit = 6}) {
    final all = cache.chatsIn(list);
    final unread = all.where((c) => c.unreadCount > 0).toList();
    final read = all.where((c) => c.unreadCount == 0);
    return FolderPreview(
      unreadMessages: unread.fold(0, (s, c) => s + c.unreadCount),
      unreadChats: unread.length,
      chats: [...unread, ...read].take(limit).toList(),
    );
  }

  String get headline => unreadChats == 0
      ? 'No unread chats'
      : '$unreadMessages unread in $unreadChats ${unreadChats == 1 ? 'chat' : 'chats'}';
}
