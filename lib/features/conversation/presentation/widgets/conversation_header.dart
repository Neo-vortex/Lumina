import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/lumina_glass.dart';
import 'typing_particles.dart';

/// Conversation header: avatar, title and a live status line (typing
/// particles, online/last seen, member or subscriber count).
class ConversationHeader extends StatelessWidget implements PreferredSizeWidget {
  const ConversationHeader({
    super.key,
    required this.chat,
    required this.showPresence,
    required this.onTitleTap,
    required this.actions,
    this.leading,
  });

  final td.Chat chat;
  final bool showPresence;
  final VoidCallback onTitleTap;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Size get preferredSize => const Size.fromHeight(66);

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final actionsInChat = cache.actionsIn(chat.id);
    final status = _status(cache);
    final peer = cache.peerUser(chat);
    final online = showPresence && peer?.status is td.UserStatusOnline && peer?.type is! td.UserTypeBot;
    // Floating liquid-glass pills over the chat (the body extends behind):
    // back, the chat itself, then one pill per action, each its own shape.
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: GlassGroup(
            shareBackdrop: true,
            child: Row(
              children: [
                GlassPill(
                  round: true,
                  child: SizedBox.square(dimension: 48, child: leading ?? const BackButton()),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GlassPill(
                    radius: 26,
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        onTap: onTitleTap,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(5, 4, 14, 4),
                          child: Row(
                            children: [
                              Hero(
                                tag: 'avatar-${chat.id}',
                                child: ChatAvatar.chat(chat, size: 40, online: online),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: _titleAndStatus(actionsInChat.isNotEmpty, status)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                for (final action in actions) ...[
                  const SizedBox(width: 8),
                  GlassPill(
                    round: true,
                    child: SizedBox.square(dimension: 48, child: Center(child: action)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _titleAndStatus(bool typing, String status) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          if (chat.type is td.ChatTypeSecret)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.lock_rounded, size: 14, color: GlowColors.cyan),
            ),
          Flexible(
            child: Text(
              chat.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.2),
            ),
          ),
        ],
      ),
      // Live line: typing particles, online in cyan, otherwise last seen or size.
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: Semantics(
          key: ValueKey(typing ? 'typing' : status),
          liveRegion: typing,
          child: typing
              ? const Row(
                  children: [
                    TypingParticles(),
                    SizedBox(width: 6),
                    Text('typing', style: TextStyle(color: GlowColors.cyan, fontSize: 12.5)),
                  ],
                )
              : Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: status == 'online' ? GlowColors.cyan : GlowColors.text.withValues(alpha: 0.7),
                  ),
                ),
        ),
      ),
    ],
  );

  String _status(TelegramCache cache) {
    final peer = cache.peerUser(chat);
    if (peer != null) return showPresence ? Display.status(peer) : (peer.type is td.UserTypeBot ? 'bot' : '');
    final sg = cache.supergroupOf(chat);
    if (sg != null) {
      final n = sg.memberCount;
      if (n == 0) return sg.isChannel ? 'channel' : 'group';
      return sg.isChannel ? '$n subscribers' : '$n members';
    }
    final bg = cache.basicGroupOf(chat);
    if (bg != null) return '${bg.memberCount} members';
    return '';
  }
}
