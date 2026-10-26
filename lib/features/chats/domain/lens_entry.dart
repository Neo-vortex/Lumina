import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/telegram_cache.dart';

/// One page of the chat list lens: All chats, a folder, or Archive.
class LensEntry {
  const LensEntry({
    required this.list,
    required this.title,
    this.folder,
    this.unread = (chats: 0, unmuted: 0),
  });

  final td.ChatList list;
  final String title;
  final td.ChatFolderInfo? folder;
  final UnreadCount unread;

  int? get folderId => folder?.id;
  String get key => TelegramCache.listKey(list);
  bool get isMain => list is td.ChatListMain;
  bool get isArchive => list is td.ChatListArchive;
}
