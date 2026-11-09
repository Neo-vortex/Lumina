import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/tdlib/td_client.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/telegram/widgets/formatted_text_view.dart';
import '../../../../core/theme/glow_colors.dart';
import 'chat_actions_sheet.dart';

/// A chat's latest messages without opening it, over a dimmed, blurred chat
/// list, with the chat's actions underneath (long-press a chat, like
/// Telegram's preview). The chat is not opened, so nothing is marked read and
/// no read receipts go out. Tap the preview to open the chat.
class ChatPeek extends StatefulWidget {
  const ChatPeek({
    super.key,
    required this.chat,
    required this.entries,
    required this.animation,
    this.onOpen,
  });

  final td.Chat chat;
  final List<ChatActionEntry> entries;
  final Animation<double> animation;
  final VoidCallback? onOpen;

  /// Pops with the [ChatActionEntry] picked, or null.
  static Route<ChatActionEntry> route(
    td.Chat chat, {
    required List<ChatActionEntry> entries,
    VoidCallback? onOpen,
  }) => PageRouteBuilder<ChatActionEntry>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, animation, _) =>
        ChatPeek(chat: chat, entries: entries, animation: animation, onOpen: onOpen),
  );

  @override
  State<ChatPeek> createState() => _ChatPeekState();
}

class _ChatPeekState extends State<ChatPeek> {
  List<td.Message>? _messages;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    _load();
  }

  /// TDLib's first history call often returns only what's cached (sometimes one
  /// message); a couple more calls fill the page. No openChat: it stays unread.
  Future<void> _load() async {
    final client = context.read<TdClient>();
    final list = <td.Message>[];
    var from = 0;
    for (var i = 0; i < 4 && list.length < 30; i++) {
      try {
        final page = await client.invoke<td.Messages>(
          td.GetChatHistory(
            chatId: widget.chat.id,
            fromMessageId: from,
            offset: 0,
            limit: 30 - list.length,
            onlyLocal: false,
          ),
        );
        final fresh = [
          for (final m in page.messages)
            if (m != null && (from == 0 || m.id != from)) m,
        ];
        if (fresh.isEmpty) break;
        list.addAll(fresh);
        from = list.last.id;
      } catch (_) {
        break;
      }
    }
    if (mounted) setState(() => _messages = list);
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final chat = widget.chat;
    final media = MediaQuery.of(context);
    final curve = CurvedAnimation(
      parent: widget.animation,
      curve: Easing.emphasizedDecelerate,
      reverseCurve: Easing.emphasizedAccelerate,
    );
    final isGroup =
        chat.type is td.ChatTypeBasicGroup || (chat.type is td.ChatTypeSupergroup && !cache.isChannel(chat));
    final status = switch (chat.type) {
      td.ChatTypePrivate(:final userId) ||
      td.ChatTypeSecret(:final userId) => Display.status(cache.users[userId]),
      _ when cache.isChannel(chat) => 'channel',
      _ => 'group',
    };
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // The list behind, dimmed and softened; a tap outside closes.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: AnimatedBuilder(
                animation: curve,
                builder: (context, _) => BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20 * curve.value, sigmaY: 20 * curve.value),
                  child: ColoredBox(color: Colors.black.withValues(alpha: 0.40 * curve.value)),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: FadeTransition(
                opacity: curve,
                child: ScaleTransition(
                  scale: Tween(begin: 0.92, end: 1.0).animate(curve),
                  child: Column(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).pop();
                            widget.onOpen?.call();
                          },
                          child: Container(
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: GlowColors.background,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              boxShadow: glow(GlowColors.violet, intensity: 0.35),
                            ),
                            child: Column(
                              children: [
                                // Header: who, and their status.
                                Container(
                                  color: GlowColors.surface,
                                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                                  child: Row(
                                    children: [
                                      ChatAvatar.chat(chat, size: 40),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              chat.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              status,
                                              maxLines: 1,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: status == 'online'
                                                    ? GlowColors.cyan
                                                    : GlowColors.textMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.open_in_full_rounded,
                                        size: 18,
                                        color: GlowColors.textMuted,
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(child: _body(cache, isGroup)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Actions, as a compact glass list (a Material, so the rows' ripples show).
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: media.size.height * 0.4),
                        child: Material(
                          color: GlowColors.surfaceHigh.withValues(alpha: 0.97),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                for (final e in widget.entries)
                                  ListTile(
                                    dense: true,
                                    leading: Icon(e.icon, color: e.color ?? GlowColors.text, size: 22),
                                    title: Text(e.label, style: TextStyle(color: e.color, fontSize: 15)),
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      Navigator.of(context).pop(e);
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(TelegramCache cache, bool isGroup) {
    final messages = _messages;
    if (messages == null) {
      return const Center(child: CircularProgressIndicator(color: GlowColors.violet, strokeWidth: 2.4));
    }
    if (messages.isEmpty) {
      return const Center(
        child: Text('No messages yet', style: TextStyle(color: GlowColors.textMuted)),
      );
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      itemCount: messages.length,
      itemBuilder: (context, i) {
        final m = messages[i];
        final newerSameSender = i > 0 && _sameSender(messages[i - 1], m);
        final olderSameSender = i < messages.length - 1 && _sameSender(messages[i + 1], m);
        if (Display.isService(m)) {
          return Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                Display.serviceText(cache, m) ?? '',
                style: const TextStyle(fontSize: 12, color: GlowColors.textMuted),
              ),
            ),
          );
        }
        return _PeekBubble(
          message: m,
          sender: isGroup && !m.isOutgoing && !olderSameSender ? Display.senderName(cache, m.senderId) : null,
          senderColor: Display.accentFor(Display.senderId(m.senderId)),
          firstInRun: !olderSameSender,
          lastInRun: !newerSameSender,
          preview: Display.preview(cache, m),
        );
      },
    );
  }

  static bool _sameSender(td.Message a, td.Message b) =>
      a.isOutgoing == b.isOutgoing &&
      Display.senderId(a.senderId) == Display.senderId(b.senderId) &&
      (a.date - b.date).abs() < 300;
}

/// A light, read-only bubble for the peek.
class _PeekBubble extends StatelessWidget {
  const _PeekBubble({
    required this.message,
    required this.preview,
    required this.firstInRun,
    required this.lastInRun,
    required this.senderColor,
    this.sender,
  });

  final td.Message message;
  final String preview;
  final String? sender;
  final Color senderColor;
  final bool firstInRun;
  final bool lastInRun;

  @override
  Widget build(BuildContext context) {
    final out = message.isOutgoing;
    const r = Radius.circular(18), tight = Radius.circular(6), tail = Radius.circular(4);
    final radius = out
        ? BorderRadius.only(
            topLeft: r,
            bottomLeft: r,
            topRight: firstInRun ? r : tight,
            bottomRight: lastInRun ? tail : tight,
          )
        : BorderRadius.only(
            topRight: r,
            bottomRight: r,
            topLeft: firstInRun ? r : tight,
            bottomLeft: lastInRun ? tail : tight,
          );
    final text = switch (message.content) {
      td.MessageText(:final text) => text,
      _ => null,
    };
    final mini = switch (message.content) {
      td.MessagePhoto(:final photo) => Display.minithumbnail(photo.minithumbnail),
      td.MessageVideo(:final video) => Display.minithumbnail(video.minithumbnail),
      _ => null,
    };
    final t = DateTime.fromMillisecondsSinceEpoch(message.date * 1000);
    final time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: EdgeInsets.only(top: firstInRun ? 8 : 2),
      child: Align(
        alignment: out ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            decoration: BoxDecoration(
              gradient: out ? GlowColors.outgoing : null,
              color: out ? null : GlowColors.bubbleIn,
              borderRadius: radius,
              border: out ? null : Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (sender != null)
                  Text(
                    sender!,
                    style: TextStyle(color: senderColor, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                if (mini != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, top: 2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                        child: Image.memory(
                          mini,
                          width: 180,
                          height: 120,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 8,
                  children: [
                    if (text != null)
                      FormattedTextView(
                        text,
                        maxLines: 8,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: out ? GlowColors.onOutgoing : GlowColors.text,
                          fontSize: 15,
                          height: 1.3,
                        ),
                      )
                    else if (mini == null)
                      Text(
                        preview,
                        style: TextStyle(
                          color: out ? GlowColors.onOutgoing : GlowColors.text,
                          fontSize: 15,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 11,
                        color: out ? GlowColors.onOutgoing.withValues(alpha: 0.7) : GlowColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
