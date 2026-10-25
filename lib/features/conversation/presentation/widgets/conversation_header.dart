import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
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
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final actionsInChat = cache.actionsIn(chat.id);
    final status = _status(cache);
    return Material(
      color: GlowColors.background,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              leading ?? const BackButton(),
              Expanded(
                child: InkWell(
                  onTap: onTitleTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Hero(tag: 'avatar-${chat.id}', child: ChatAvatar.chat(chat, size: 40)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
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
                                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                              Semantics(
                                liveRegion: actionsInChat.isNotEmpty,
                                child: actionsInChat.isNotEmpty
                                    ? const Row(
                                        children: [
                                          TypingParticles(),
                                          SizedBox(width: 6),
                                          Text(
                                            'typing',
                                            style: TextStyle(color: GlowColors.cyan, fontSize: 13),
                                          ),
                                        ],
                                      )
                                    : Text(
                                        status,
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: status == 'online' ? GlowColors.cyan : GlowColors.textMuted,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }

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
