import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../data/chats_repository.dart';
import 'chat_list_extensions.dart';

/// Long-press actions on a chat row.
Future<void> showChatActions(
  BuildContext context,
  td.Chat chat, {
  td.ChatList list = const td.ChatListMain(),
}) async {
  Feedback.forLongPress(context);
  final repo = context.read<ChatsRepository>();
  final cache = context.read<TelegramCache>();
  final pinned = cache.positionIn(chat, list)?.isPinned ?? false;
  final muted = cache.isMuted(chat);
  final unread = chat.unreadCount > 0 || chat.isMarkedAsUnread;
  final isGroupish = chat.type is td.ChatTypeBasicGroup || chat.type is td.ChatTypeSupergroup;
  final messenger = ScaffoldMessenger.of(context);
  final outer = context;
  final extra = ChatListExtensions.of(context).chatActions(chat);

  Future<void> run(Future<void> Function() action) async {
    Navigator.of(context).pop();
    try {
      await action();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: GlowColors.surfaceHigh,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded),
            title: Text(pinned ? 'Unpin' : 'Pin'),
            onTap: () => run(() => repo.setPinned(chat.id, !pinned, list: list)),
          ),
          ListTile(
            leading: Icon(unread ? Icons.mark_chat_read_rounded : Icons.mark_chat_unread_rounded),
            title: Text(unread ? 'Mark as read' : 'Mark as unread'),
            onTap: () => run(() => unread ? repo.markRead(chat) : repo.setMarkedUnread(chat.id, true)),
          ),
          ListTile(
            leading: Icon(muted ? Icons.notifications_rounded : Icons.notifications_off_rounded),
            title: Text(muted ? 'Unmute' : 'Mute'),
            onTap: () => run(() => repo.setMuted(chat.id, !muted)),
          ),
          for (final a in extra)
            ListTile(
              leading: Icon(a.icon),
              title: Text(a.label),
              onTap: () {
                Navigator.of(context).pop();
                a.run(outer).ignore();
              },
            ),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: GlowColors.coral),
            title: Text(
              isGroupish ? (cache.isChannel(chat) ? 'Leave channel' : 'Leave group') : 'Delete chat',
              style: const TextStyle(color: GlowColors.coral),
            ),
            onTap: () => run(() => repo.leaveOrDelete(chat)),
          ),
        ],
      ),
    ),
  );
}
