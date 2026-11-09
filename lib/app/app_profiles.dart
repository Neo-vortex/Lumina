import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../core/tdlib/td_client.dart';
import '../core/tdlib/td_errors.dart';
import '../core/telegram/profile_opener.dart';
import '../core/telegram/telegram_cache.dart';
import '../core/theme/glow_colors.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/auth/domain/auth_step.dart';
import '../features/bots/presentation/bot_profile_section.dart';
import '../features/calls/bloc/call_cubit.dart';
import '../features/chat_info/presentation/compose_flows.dart';
import '../features/folders/presentation/screens/folder_qr_screen.dart';
import '../features/profile/presentation/my_account_screen.dart';
import '../features/profile/presentation/user_profile_screen.dart';

/// A person's full profile, the same from chat info, mentions and links.
/// [chatBehind]: the private chat is right under the profile, so "Message"
/// just goes back to it; otherwise it opens (or creates) the chat.
Route<void> userProfileRoute(
  BuildContext context,
  int userId,
  ComposeFlows flows, {
  bool chatBehind = false,
}) => MaterialPageRoute<void>(
  builder: (_) => UserProfileScreen(
    userId: userId,
    onMessage: (id) async {
      if (chatBehind) {
        Navigator.of(context).maybePop();
        return;
      }
      final client = context.read<TdClient>();
      final chat = await client.invoke<td.Chat>(td.CreatePrivateChat(userId: id, force: false));
      if (context.mounted) flows.openChat(context, chat.id);
    },
    botSection: (context, user, full) => BotProfileSection(info: full.botInfo!),
    onCall: (id, {required video}) async {
      final messenger = ScaffoldMessenger.of(context);
      final error = await context.read<CallCubit>().startCall(id, video: video);
      if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
    },
    onOpenChat: (id) => flows.openChat(context, id),
    onShowQr: (url, title) =>
        Navigator.of(context).push(FolderQrScreen.route(url: url, title: title, color: GlowColors.violet)),
  ),
);

/// What mentions and t.me/username links open, like Telegram: people get
/// their profile, bots, groups and channels their chat, you your account.
ProfileOpener appProfileOpener(ComposeFlows flows) {
  Future<void> openUser(BuildContext context, int userId) async {
    final step = context.read<AuthBloc>().state.step;
    if (step is AuthReady && step.me.id == userId && !step.capabilities.isBot) {
      await Navigator.of(context).push(MyAccountScreen.route(userId));
      return;
    }
    final cache = context.read<TelegramCache>();
    var user = cache.users[userId];
    if (user == null) {
      try {
        user = await context.read<TdClient>().invoke<td.User>(td.GetUser(userId: userId));
      } on TdException {
        if (context.mounted) _snack(context, 'This user is not available');
        return;
      }
    }
    if (!context.mounted) return;
    if (user.type is td.UserTypeBot) {
      final chat = await context.read<TdClient>().invoke<td.Chat>(
        td.CreatePrivateChat(userId: userId, force: false),
      );
      if (context.mounted) flows.openChat(context, chat.id);
      return;
    }
    await Navigator.of(context).push(userProfileRoute(context, userId, flows));
  }

  Future<void> openUsername(BuildContext context, String username) async {
    final name = username.replaceFirst('@', '');
    td.Chat chat;
    try {
      chat = await context.read<TdClient>().invoke<td.Chat>(td.SearchPublicChat(username: name));
    } on TdException {
      if (context.mounted) _snack(context, 'Nobody uses @$name');
      return;
    }
    if (!context.mounted) return;
    if (chat.type case td.ChatTypePrivate(:final userId)) return openUser(context, userId);
    flows.openChat(context, chat.id);
  }

  return ProfileOpener(openUser: openUser, openUsername: openUsername);
}

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
