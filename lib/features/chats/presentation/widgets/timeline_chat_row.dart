import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';
import 'chat_row_extensions.dart';

/// One chat on the timeline ribbon: a glowing node on a vertical thread,
/// then avatar, title, preview, time and unread count.
///
/// Node size grows with unread count, glow with recency (spec §9.2). When a
/// new incoming message arrives the node pulses once (spec §9.3).
class TimelineChatRow extends StatefulWidget {
  const TimelineChatRow({
    super.key,
    required this.chat,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
    this.onLongPress,
    this.showPresence = true,
  });

  final td.Chat chat;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showPresence;

  @override
  State<TimelineChatRow> createState() => _TimelineChatRowState();
}

class _TimelineChatRowState extends State<TimelineChatRow> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: Motion.pulse);

  @override
  void didUpdateWidget(TimelineChatRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.chat.lastMessage, after = widget.chat.lastMessage;
    if (after != null && before?.id != after.id && !after.isOutgoing && Motion.ambientEnabled(context)) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final chat = widget.chat;
    final now = DateTime.now();
    final last = chat.lastMessage;
    final lastDate = last != null ? Display.messageDate(last) : null;
    final unread = chat.unreadCount + (chat.isMarkedAsUnread && chat.unreadCount == 0 ? 1 : 0);
    final muted = chat.notificationSettings.muteFor > 0;
    final pinned = cache.positionIn(chat, const td.ChatListMain())?.isPinned ?? false;
    final peer = cache.peerUser(chat);
    final online =
        widget.showPresence && peer?.status is td.UserStatusOnline && peer?.type is! td.UserTypeBot;
    final actions = cache.actionsIn(chat.id);

    // Recency 1 → just now, 0 → a week or older.
    final ageHours = lastDate == null ? 1e9 : now.difference(lastDate).inMinutes / 60;
    final recency = (1 - (math.log(1 + ageHours) / math.log(1 + 24 * 7))).clamp(0.0, 1.0);
    final nodeSize = 8.0 + 10.0 * (math.min(unread, 20) / 20);
    final accent = unread > 0 && !muted ? GlowColors.cyan : GlowColors.violet;

    final draft = chat.draftMessage;
    final Widget preview;
    if (actions.isNotEmpty) {
      preview = Text(
        _actionText(cache, chat, actions),
        style: const TextStyle(color: GlowColors.cyan, fontStyle: FontStyle.italic),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else if (draft != null) {
      final draftText = switch (draft.inputMessageText) {
        td.InputMessageText(:final text) => text.text,
        _ => '',
      };
      preview = Text.rich(
        TextSpan(
          children: [
            const TextSpan(
              text: 'Draft: ',
              style: TextStyle(color: GlowColors.coral),
            ),
            TextSpan(text: draftText),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: GlowColors.textMuted),
      );
    } else {
      final sender =
          last != null && !last.isOutgoing && chat.type is! td.ChatTypePrivate && !cache.isChannel(chat)
          ? '${Display.senderName(cache, last.senderId).split(' ').first}: '
          : (last?.isOutgoing ?? false)
          ? 'You: '
          : '';
      preview = Text(
        '$sender${Display.preview(cache, last)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: GlowColors.textMuted),
      );
    }

    final read = last != null && last.isOutgoing && last.id <= chat.lastReadOutboxMessageId;

    return Semantics(
      button: true,
      label: [
        chat.title,
        if (unread > 0) '$unread unread',
        if (muted) 'muted',
        if (pinned) 'pinned',
        if (lastDate != null) Display.listTime(lastDate, now),
        if (actions.isEmpty) Display.preview(cache, last),
      ].join(', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: SizedBox(
          height: 76,
          child: Row(
            children: [
              // The ribbon: thread + node.
              SizedBox(
                width: 36,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => CustomPaint(
                    size: const Size(36, 76),
                    painter: _RibbonPainter(
                      nodeSize: nodeSize * (1 + 0.5 * math.sin(_pulse.value * math.pi)),
                      glow: math.max(recency, _pulse.value == 0 ? 0 : 1 - _pulse.value),
                      color: accent,
                      isFirst: widget.isFirst,
                      isLast: widget.isLast,
                    ),
                  ),
                ),
              ),
              _decoratedAvatar(
                context,
                chat,
                ChatAvatar.chat(chat, size: 50, glowIntensity: unread > 0 ? 0.35 : 0, online: online),
              ),
              const SizedBox(width: 10),
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
                        Expanded(
                          child: Text(
                            chat.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (muted)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.notifications_off_rounded,
                              size: 14,
                              color: GlowColors.textMuted,
                            ),
                          ),
                        if (last != null && last.isOutgoing)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: _ReadMark(read: read),
                          ),
                        if (lastDate != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              Display.listTime(lastDate, now),
                              style: TextStyle(
                                fontSize: 12,
                                color: unread > 0 ? GlowColors.cyan : GlowColors.textMuted,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(child: preview),
                        if (chat.unreadMentionCount > 0)
                          const _Badge(text: '@', color: GlowColors.magentaDeep),
                        if (unread > 0)
                          _Badge(
                            text: unread > 999 ? '999+' : '$unread',
                            color: muted ? GlowColors.surfaceHigh : GlowColors.teal,
                            foreground: muted ? GlowColors.textMuted : GlowColors.onAccent,
                          )
                        else if (pinned)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.push_pin_rounded, size: 14, color: GlowColors.textMuted),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }

  static String _actionText(
    TelegramCache cache,
    td.Chat chat,
    List<({td.MessageSender sender, td.ChatAction action})> actions,
  ) {
    final verb = switch (actions.first.action) {
      td.ChatActionRecordingVoiceNote() => 'recording audio',
      td.ChatActionRecordingVideoNote() || td.ChatActionRecordingVideo() => 'recording video',
      td.ChatActionUploadingPhoto() => 'sending a photo',
      td.ChatActionUploadingVideo() || td.ChatActionUploadingVideoNote() => 'sending a video',
      td.ChatActionUploadingDocument() => 'sending a file',
      td.ChatActionUploadingVoiceNote() => 'sending audio',
      td.ChatActionChoosingSticker() => 'choosing a sticker',
      _ => 'typing',
    };
    if (chat.type is td.ChatTypePrivate || chat.type is td.ChatTypeSecret) return '$verb…';
    final names = actions.map((a) => Display.senderName(cache, a.sender).split(' ').first).toList();
    return names.length == 1 ? '${names.first} is $verb…' : '${names.length} people are $verb…';
  }
}

/// Read state as an edge-glow shift plus a shape change (UX-04): a hollow
/// ring while delivered, a filled glowing dot once read.
Widget _decoratedAvatar(BuildContext context, td.Chat chat, Widget avatar) {
  ChatRowExtensions ext;
  try {
    ext = context.read<ChatRowExtensions>();
  } on ProviderNotFoundException {
    ext = const ChatRowExtensions();
  }
  final listenable = ext.listenable;
  if (listenable == null) return ext.avatar(context, chat, avatar, 50);
  return ListenableBuilder(
    listenable: listenable,
    builder: (context, _) => ext.avatar(context, chat, avatar, 50),
  );
}

class _ReadMark extends StatelessWidget {
  const _ReadMark({required this.read});

  final bool read;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: read ? 'read' : 'sent',
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: read ? GlowColors.cyan : Colors.transparent,
          border: Border.all(color: read ? GlowColors.cyan : GlowColors.textMuted, width: 1.4),
          boxShadow: read ? glow(GlowColors.cyan, intensity: 0.5) : null,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color, this.foreground = Colors.white});

  final String text;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(11)),
      child: Text(
        text,
        style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter({
    required this.nodeSize,
    required this.glow,
    required this.color,
    required this.isFirst,
    required this.isLast,
  });

  final double nodeSize;
  final double glow;
  final Color color;
  final bool isFirst;
  final bool isLast;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2 + 2, cy = size.height / 2;
    final thread = Paint()
      ..strokeWidth = 2
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [GlowColors.violet.withValues(alpha: 0.35), GlowColors.teal.withValues(alpha: 0.35)],
      ).createShader(Offset.zero & size);
    canvas.drawLine(Offset(cx, isFirst ? cy : 0), Offset(cx, isLast ? cy : size.height), thread);
    if (glow > 0.05) {
      canvas.drawCircle(
        Offset(cx, cy),
        nodeSize * (1.2 + glow),
        Paint()
          ..color = color.withValues(alpha: 0.25 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + 8 * glow),
      );
    }
    canvas.drawCircle(
      Offset(cx, cy),
      nodeSize / 2,
      Paint()..color = Color.lerp(GlowColors.outlineStrong, color, 0.3 + 0.7 * glow)!,
    );
  }

  @override
  bool shouldRepaint(_RibbonPainter old) =>
      old.nodeSize != nodeSize ||
      old.glow != glow ||
      old.color != color ||
      old.isFirst != isFirst ||
      old.isLast != isLast;
}
