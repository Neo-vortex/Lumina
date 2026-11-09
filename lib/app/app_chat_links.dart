import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../core/tdlib/td_client.dart';
import '../core/tdlib/td_errors.dart';
import '../core/telegram/internal_links.dart';
import '../core/telegram/widgets/chat_avatar.dart';
import '../core/theme/glow_colors.dart';
import '../core/widgets/glow_button.dart';
import '../core/widgets/glow_sheet.dart';
import '../features/conversation/presentation/screens/conversation_screen.dart';

/// Group and channel invite links (t.me/+hash, t.me/joinchat/hash,
/// tg://join?invite=hash) and message links (t.me/name/123, t.me/c/id/123,
/// tg://resolve?domain=name&post=123, tg://privatepost) open in the app:
/// the chat itself, or a preview to join first.
List<InternalLinkHandler> chatLinkHandlers() => [
  InternalLinkHandler(matches: isInviteLink, open: openInviteLink),
  InternalLinkHandler(matches: isMessageLink, open: openMessageLink),
];

bool _telegramHost(Uri uri) {
  final h = uri.host.toLowerCase();
  return (uri.scheme == 'https' || uri.scheme == 'http') &&
      (h == 't.me' || h == 'telegram.me' || h == 'www.t.me');
}

List<String> _segments(Uri uri) => uri.pathSegments.where((s) => s.isNotEmpty).toList();

bool isInviteLink(Uri uri) {
  if (uri.scheme == 'tg') return uri.host == 'join' && (uri.queryParameters['invite'] ?? '').isNotEmpty;
  if (!_telegramHost(uri)) return false;
  final s = _segments(uri);
  return s.isNotEmpty &&
      ((s.first.startsWith('+') && s.first.length > 1) || (s.first == 'joinchat' && s.length > 1));
}

bool isMessageLink(Uri uri) {
  if (uri.scheme == 'tg') {
    return (uri.host == 'resolve' && uri.queryParameters.containsKey('post')) || uri.host == 'privatepost';
  }
  if (!_telegramHost(uri)) return false;
  final s = _segments(uri);
  final isId = RegExp(r'^\d+$');
  // t.me/name/123, t.me/name/123?comment=4, t.me/c/1234/56, t.me/c/1234/7/56 (topics).
  if (s.length >= 3 && s.first == 'c') return isId.hasMatch(s[1]) && isId.hasMatch(s.last);
  return s.length >= 2 && !s.first.startsWith('+') && s.first != 'joinchat' && isId.hasMatch(s[1]);
}

void _snack(BuildContext context, String text) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<void> openMessageLink(BuildContext context, Uri uri) async {
  final client = context.read<TdClient>();
  final nav = Navigator.of(context);
  try {
    final info = await client.invoke<td.MessageLinkInfo>(td.GetMessageLinkInfo(url: uri.toString()));
    if (info.chatId == 0) return _snack(context, 'This message isn\'t available');
    await nav.push(ConversationScreen.route(info.chatId, focusMessageId: info.message?.id));
  } on TdException catch (e) {
    if (context.mounted) _snack(context, e.message);
  }
}

Future<void> openInviteLink(BuildContext context, Uri uri) async {
  final client = context.read<TdClient>();
  final nav = Navigator.of(context);
  final link = uri.toString();
  final td.ChatInviteLinkInfo info;
  try {
    info = await client.invoke<td.ChatInviteLinkInfo>(td.CheckChatInviteLink(inviteLink: link));
  } on TdException catch (e) {
    final expired = e.message.contains('INVITE_HASH_EXPIRED') || e.message.contains('INVITE_HASH_INVALID');
    if (context.mounted) _snack(context, expired ? 'This invite link has expired or was revoked' : e.message);
    return;
  }
  // Already a member (or a public chat you can read): straight in.
  if (info.chatId != 0 && info.accessibleFor == 0) {
    await nav.push(ConversationScreen.route(info.chatId));
    return;
  }
  if (!context.mounted) return;
  final join = await showGlowSheet<bool>(context, builder: (context) => _InvitePreview(info: info));
  if (join != true || !context.mounted) return;
  try {
    final chat = await client.invoke<td.Chat>(td.JoinChatByInviteLink(inviteLink: link));
    await nav.push(ConversationScreen.route(chat.id));
  } on TdException catch (e) {
    if (!context.mounted) return;
    // Links that need approval: the request is sent, there's no chat yet.
    if (info.createsJoinRequest || e.message.contains('INVITE_REQUEST_SENT')) {
      _snack(context, 'Request sent. An admin will let you in.');
    } else {
      _snack(context, e.message);
    }
  }
}

class _InvitePreview extends StatelessWidget {
  const _InvitePreview({required this.info});

  final td.ChatInviteLinkInfo info;

  @override
  Widget build(BuildContext context) {
    final (kind, people) = switch (info.type) {
      td.InviteLinkChatTypeChannel() => ('Channel', 'subscribers'),
      _ => ('Group', 'members'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChatAvatar(id: info.chatId, title: info.title, photo: info.photo, size: 84, glowIntensity: 0.5),
          const SizedBox(height: 14),
          Text(
            info.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '$kind · ${_count(info.memberCount)} $people',
            style: const TextStyle(color: GlowColors.textMuted),
          ),
          if (info.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              info.description,
              textAlign: TextAlign.center,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: GlowColors.text),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: GlowButton(
              label: info.createsJoinRequest
                  ? 'Request to join'
                  : kind == 'Channel'
                  ? 'Join channel'
                  : 'Join group',
              onPressed: () => Navigator.pop(context, true),
            ),
          ),
        ],
      ),
    );
  }
}

String _count(int n) => n >= 1000000
    ? '${(n / 1000000).toStringAsFixed(1)}M'
    : n >= 10000
    ? '${(n / 1000).round()}K'
    : '$n';
