import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/widgets/chat_scrolling.dart';
import '../../../../core/widgets/delivery_ticks.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';
import 'chat_list_extensions.dart';
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
    this.tint,
  });

  /// Every row is this tall (the list relies on it).
  static const height = 72.0;

  final td.Chat chat;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showPresence;

  /// The lens colour; null keeps the default violet/teal ribbon.
  final Color? tint;

  @override
  State<TimelineChatRow> createState() => _TimelineChatRowState();
}

class _TimelineChatRowState extends State<TimelineChatRow> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: Motion.pulse);
  var _lastPulse = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didUpdateWidget(TimelineChatRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.chat.lastMessage, after = widget.chat.lastMessage;
    if (after == null || before?.id == after.id || after.isOutgoing || !Motion.ambientEnabled(context)) return;
    // Each pulse animates the row at the display rate. Busy channels (muted,
    // several posts a second) kept some row pulsing at all times, so the
    // list never went idle and every scroll frame carried the pulses too.
    // Only chats that notify you pulse, at most every few seconds, and
    // never while the list moves.
    final now = DateTime.now();
    if (context.read<TelegramCache>().isMuted(widget.chat) ||
        ChatScrolling.moving.value ||
        _pulse.isAnimating ||
        now.difference(_lastPulse) < const Duration(seconds: 4)) {
      return;
    }
    _lastPulse = now;
    _pulse.forward(from: 0);
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
    final muted = cache.isMuted(chat);
    final pinned = cache.positionIn(chat, const td.ChatListMain())?.isPinned ?? false;
    final sponsored = cache.isProxySponsored(chat);
    final peer = cache.peerUser(chat);
    final online =
        widget.showPresence && peer?.status is td.UserStatusOnline && peer?.type is! td.UserTypeBot;
    final actions = cache.actionsIn(chat.id);

    // Recency 1 → just now, 0 → a week or older.
    final ageHours = lastDate == null ? 1e9 : now.difference(lastDate).inMinutes / 60;
    final recency = (1 - (math.log(1 + ageHours) / math.log(1 + 24 * 7))).clamp(0.0, 1.0);
    final nodeSize = 8.0 + 10.0 * (math.min(unread, 20) / 20);
    final tint = widget.tint;
    final accent = unread > 0 && !muted ? (tint ?? GlowColors.cyan) : (tint ?? GlowColors.violet);

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
      final draftText = switch (draft.content) {
        td.DraftMessageContentText(:final text) => text.text,
        _ => '',
      };
      preview = Text.rich(
        TextSpan(
          children: [
            const TextSpan(
              text: 'Draft: ',
              style: TextStyle(color: GlowColors.coral),
            ),
            TextSpan(text: _oneLine(draftText)),
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
        _oneLine('$sender${Display.preview(cache, last)}'),
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
        if (sponsored) 'proxy sponsor',
        if (muted) 'muted',
        if (pinned) 'pinned',
        if (lastDate != null) Display.listTime(lastDate, now),
        if (actions.isEmpty) _oneLine(Display.preview(cache, last)),
      ].join(', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: SizedBox(
          height: TimelineChatRow.height, // Telegram's row is 70 dp (DialogCell); a touch more air
          child: Row(
            children: [
              // The ribbon: thread + node.
              SizedBox(
                width: 36,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => CustomPaint(
                    size: const Size(36, TimelineChatRow.height),
                    painter: _RibbonPainter(
                      tint: tint,
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
                ChatAvatar.chat(chat, size: 52, glowIntensity: unread > 0 ? 0.35 : 0, online: online),
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
                        if (sponsored) const _SponsorTag(),
                        ...ChatListExtensions.of(context).folderTags(context, chat),
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
                        // Pinned shows next to the counters, never under them.
                        if (pinned && (unread > 0 || chat.unreadMentionCount > 0))
                          const Padding(
                            padding: EdgeInsets.only(left: 6, right: 2),
                            child: Icon(Icons.push_pin_rounded, size: 14, color: GlowColors.textMuted),
                          ),
                        if (chat.unreadMentionCount > 0)
                          const _Badge(text: '@', color: GlowColors.magentaDeep),
                        if (unread > 0)
                          _Badge(
                            text: unread > 999 ? '999+' : '$unread',
                            // Cyan with dark text (12.2 : 1); muted chats a quiet grey pill.
                            color: muted ? const Color(0xFF3A4150) : GlowColors.cyan,
                            foreground: muted ? const Color(0xFFC3CAD5) : GlowColors.onAccent,
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

  /// What one row line can show. Channel posts run to thousands of
  /// characters, and Flutter shapes a paragraph's whole text before it
  /// ellipsizes: each such row cost over a millisecond of layout as it
  /// scrolled in (the chat list's stutter). Newlines go too (one line).
  static String _oneLine(String text) {
    var end = text.length;
    if (end > 120) {
      end = 120;
      // Never split an emoji's surrogate pair.
      final unit = text.codeUnitAt(end - 1);
      if (unit >= 0xD800 && unit <= 0xDBFF) end--;
    }
    final cut = end == text.length ? text : text.substring(0, end);
    return cut.contains('\n') ? cut.replaceAll(_newlines, ' ') : cut;
  }

  static final _newlines = RegExp(r'\s*\n\s*');

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
      child: DeliveryTicks(
        state: read ? TickState.read : TickState.sent,
        color: GlowColors.textMuted,
        readColor: GlowColors.ocean,
        size: 14,
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

/// Marks the channel the active MTProto proxy promotes.
class _SponsorTag extends StatelessWidget {
  const _SponsorTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: GlowColors.amber.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Proxy sponsor',
        style: TextStyle(color: GlowColors.amber, fontSize: 11, fontWeight: FontWeight.w600),
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
    required this.tint,
  });

  final double nodeSize;
  final double glow;
  final Color color;
  final bool isFirst;
  final bool isLast;
  final Color? tint;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2 + 2, cy = size.height / 2;
    final from = Offset(cx, isFirst ? cy : 0), to = Offset(cx, isLast ? cy : size.height);
    final colors = tint == null
        ? [GlowColors.violet, GlowColors.cyan]
        : [tint!, Color.lerp(tint, GlowColors.cyan, 0.35)!];
    Shader shader(double a, double b) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        colors.first.withValues(alpha: a),
        colors.last.withValues(alpha: b),
      ],
    ).createShader(Offset.zero & size);
    // A soft halo along the thread, then the thread itself: one line that
    // visibly links the chats, brighter near recent ones. No mask blurs
    // anywhere here: Impeller redraws every row each scroll frame, and ~20
    // blurs a frame made the list stutter. Wide faint strokes read the same.
    canvas.drawLine(
      from,
      to,
      Paint()
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..shader = shader(0.07 + 0.08 * glow, 0.05 + 0.08 * glow),
    );
    canvas.drawLine(
      from,
      to,
      Paint()
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..shader = shader(0.12 + 0.12 * glow, 0.08 + 0.12 * glow),
    );
    canvas.drawLine(
      from,
      to,
      Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..shader = shader(0.55 + 0.3 * glow, 0.4 + 0.3 * glow),
    );
    final node = Offset(cx, cy);
    // Glow around the node: always a little, more for recent chats. A radial
    // gradient, not a blur.
    final glowR = nodeSize * (1.6 + 1.4 * glow);
    canvas.drawCircle(
      node,
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.30 + 0.30 * glow),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: node, radius: glowR)),
    );
    // A dark ring cuts the node out of the thread, then the bead.
    canvas.drawCircle(node, nodeSize / 2 + 2, Paint()..color = GlowColors.background.withValues(alpha: 0.85));
    canvas.drawCircle(
      node,
      nodeSize / 2,
      Paint()..color = Color.lerp(colors.first, color, 0.4 + 0.6 * glow)!,
    );
    // A bright core makes it read as light rather than paint.
    canvas.drawCircle(node, nodeSize / 5, Paint()..color = Colors.white.withValues(alpha: 0.35 + 0.4 * glow));
  }

  @override
  bool shouldRepaint(_RibbonPainter old) =>
      old.nodeSize != nodeSize ||
      old.glow != glow ||
      old.color != color ||
      old.tint != tint ||
      old.isFirst != isFirst ||
      old.isLast != isLast;
}
