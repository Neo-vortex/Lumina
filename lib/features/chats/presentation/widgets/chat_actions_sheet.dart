import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/delete_confirm.dart';
import '../../data/chats_repository.dart';
import 'chat_list_extensions.dart';
import 'chat_peek.dart';

/// One action on a chat (pin, mute, leave…), shared by the chat peek and its fallback sheet.
class ChatActionEntry {
  const ChatActionEntry(this.icon, this.label, this.run, {this.color});
  final IconData icon;
  final String label;
  final Color? color;

  /// Runs with the chat list's context (still mounted after the peek closes).
  final Future<void> Function(BuildContext context) run;
}

/// The actions for [chat] in [list], in display order.
List<ChatActionEntry> chatActionEntries(
  BuildContext context,
  td.Chat chat, {
  td.ChatList list = const td.ChatListMain(),
}) {
  final repo = context.read<ChatsRepository>();
  final cache = context.read<TelegramCache>();
  final pinned = cache.positionIn(chat, list)?.isPinned ?? false;
  final muted = cache.isMuted(chat);
  final unread = chat.unreadCount > 0 || chat.isMarkedAsUnread;
  final isGroupish = chat.type is td.ChatTypeBasicGroup || chat.type is td.ChatTypeSupergroup;
  Future<void> Function(BuildContext) guarded(Future<void> Function() action) => (context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  };
  return [
    ChatActionEntry(
      pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
      pinned ? 'Unpin' : 'Pin',
      guarded(() => repo.setPinned(chat.id, !pinned, list: list)),
    ),
    ChatActionEntry(
      unread ? Icons.mark_chat_read_rounded : Icons.mark_chat_unread_rounded,
      unread ? 'Mark as read' : 'Mark as unread',
      guarded(() => unread ? repo.markRead(chat) : repo.setMarkedUnread(chat.id, true)),
    ),
    ChatActionEntry(
      muted ? Icons.notifications_rounded : Icons.notifications_off_rounded,
      muted ? 'Unmute' : 'Mute',
      guarded(() => repo.setMuted(chat.id, !muted)),
    ),
    for (final a in ChatListExtensions.of(context).chatActions(chat)) ChatActionEntry(a.icon, a.label, a.run),
    ChatActionEntry(
      Icons.logout_rounded,
      isGroupish ? (cache.isChannel(chat) ? 'Leave channel' : 'Leave group') : 'Delete chat',
      (context) => confirmAndDeleteChat(context, chat),
      color: GlowColors.coral,
    ),
  ];
}

/// Long-press on a chat row: the chat's latest messages without opening it
/// (nothing is marked read), with its actions underneath.
Future<void> showChatActions(
  BuildContext context,
  td.Chat chat, {
  td.ChatList list = const td.ChatListMain(),
  VoidCallback? onOpen,
}) async {
  Feedback.forLongPress(context);
  final entries = chatActionEntries(context, chat, list: list);
  final picked = await Navigator.of(context)
      .push<ChatActionEntry>(ChatPeek.route(chat, entries: entries, onOpen: onOpen));
  if (picked != null && context.mounted) await picked.run(context);
}

/// Every chat delete or leave confirms; private chats offer "also delete
/// for {name}" when TDLib allows it.
Future<void> confirmAndDeleteChat(BuildContext context, td.Chat chat) async {
  final repo = context.read<ChatsRepository>();
  final cache = context.read<TelegramCache>();
  final messenger = ScaffoldMessenger.of(context);
  final private = chat.type is td.ChatTypePrivate || chat.type is td.ChatTypeSecret;
  final channel = cache.isChannel(chat);
  final forBoth = await confirmDelete(
    context,
    title: private ? 'Delete chat with ${chat.title}?' : 'Leave ${chat.title}?',
    message: private ? null : (channel ? 'You will stop receiving its posts.' : 'You will leave the group.'),
    confirmLabel: private ? 'Delete' : 'Leave',
    alsoLabel: private && chat.canBeDeletedForAllUsers
        ? 'Also delete for ${cache.peerUser(chat)?.firstName ?? chat.title}'
        : null,
  );
  if (forBoth == null) return;
  try {
    await repo.leaveOrDelete(chat, forBoth: forBoth);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}
