import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:intl/intl.dart';

import '../../../../core/telegram/display.dart';
import '../../../../core/gestures/swipe_actions.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';
import '../../bloc/conversation_cubit.dart';
import 'content/message_content_view.dart';
import 'message_rows.dart';
import 'reactions_row.dart';

/// Delivery state of an outgoing message.
enum Delivery { pending, failed, sent, read }

/// Shared: building a [DateFormat] parses its pattern each time.
final _hm = DateFormat.Hm();

/// A glowing message bubble (spec §9.2).
class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.row,
    required this.chat,
    required this.isGroup,
    required this.isChannel,
    required this.animateIn,
    required this.highlighted,
    required this.selected,
    required this.selecting,
    this.swipeLeft = MessageSwipe.reply,
    this.swipeRight = MessageSwipe.none,
    this.swipeEmoji = '❤️',
    required this.onSwipe,
    required this.onLongPress,
    required this.onTap,
    this.onMenu,
    required this.onReplyQuoteTap,
    required this.onReaction,
  });

  final BubbleRow row;
  final td.Chat chat;
  final bool isGroup;
  final bool isChannel;
  final bool animateIn;
  final bool highlighted;
  final bool selected;
  final bool selecting;

  /// What swiping toward each edge does (Settings → Swipe gestures).
  final MessageSwipe swipeLeft;
  final MessageSwipe swipeRight;
  final String swipeEmoji;
  final ValueChanged<SwipeSide> onSwipe;
  final VoidCallback onLongPress;
  final VoidCallback onTap;

  /// Opens the message menu, given where the bubble sits on screen (the
  /// menu redraws it there, lifted). Taps go to [onTap] while selecting.
  final ValueChanged<Rect>? onMenu;
  final void Function(int messageId) onReplyQuoteTap;
  final void Function(String emoji) onReaction;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(vsync: this, duration: Motion.standard);
  late final CurvedAnimation _entranceCurve = CurvedAnimation(parent: _entrance, curve: Motion.enter);
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, 0.25),
    end: Offset.zero,
  ).animate(_entranceCurve);

  /// Only bubbles that play the entrance get the fade and slide wrappers.
  bool _animates = false;
  late final AnimationController _bloom = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  double _drag = 0;
  final _bubbleKey = GlobalKey();
  bool _crossed = false;

  static const _replyThreshold = 64.0;

  bool _entered = false;

  // Here, not initState: reduced motion comes from MediaQuery.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entered) return;
    _entered = true;
    if (widget.animateIn && Motion.ambientEnabled(context)) {
      _animates = true;
      _entrance.forward();
      if (widget.row.primary.isOutgoing) _bloom.forward();
    } else {
      _entrance.value = 1;
    }
  }

  @override
  void dispose() {
    if (_animates) _entranceCurve.dispose();
    _entrance.dispose();
    _bloom.dispose();
    super.dispose();
  }

  Delivery _delivery(td.Message m) => switch (m.sendingState) {
    td.MessageSendingStatePending() => Delivery.pending,
    td.MessageSendingStateFailed() => Delivery.failed,
    null => m.id <= widget.chat.lastReadOutboxMessageId ? Delivery.read : Delivery.sent,
  };

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final row = widget.row;
    final m = row.primary;
    final outgoing = m.isOutgoing && !widget.isChannel;
    final delivery = m.isOutgoing ? _delivery(m) : Delivery.sent;
    final ambient = Motion.ambientEnabled(context);

    // Asymmetric: the sender's side is tight inside a run, round elsewhere.
    const r = Radius.circular(20), tight = Radius.circular(6);
    final radius = outgoing
        ? BorderRadius.only(
            topLeft: r,
            bottomLeft: r,
            topRight: row.firstInRun ? r : tight,
            bottomRight: tight,
          )
        : BorderRadius.only(
            topRight: r,
            bottomRight: r,
            topLeft: row.firstInRun ? r : tight,
            bottomLeft: tight,
          );

    final textColor = outgoing ? GlowColors.onOutgoing : GlowColors.text;
    final mutedColor = outgoing ? GlowColors.onOutgoing.withValues(alpha: 0.65) : GlowColors.textMuted;
    final edge = switch (delivery) {
      Delivery.read => GlowColors.cyan,
      Delivery.failed => GlowColors.error,
      Delivery.pending => GlowColors.amber.withValues(alpha: 0.3),
      Delivery.sent => GlowColors.amber.withValues(alpha: 0.6),
    };
    final edgeColor = outgoing
        ? edge
        : (widget.highlighted ? GlowColors.violet : GlowColors.cyan.withValues(alpha: 0.35));

    final senderName = widget.isGroup && !outgoing && row.firstInRun
        ? Display.senderName(cache, m.senderId)
        : null;
    final media = isMediaContent(m.content);
    // Round videos stand alone, like Telegram: just the circle, no bubble.
    final bare = m.content is td.MessageVideoNote;

    final bubble = AnimatedBuilder(
      animation: _bloom,
      builder: (context, child) {
        final bloom = ambient
            ? Curves.easeOut.transform(1 - _bloom.value) * (_bloom.isAnimating ? 1 : 0)
            : 0.0;
        final dragGlow = (_drag.abs() / _replyThreshold).clamp(0.0, 1.0);
        return Container(
          key: _bubbleKey,
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * (media ? 0.78 : 0.8)),
          decoration: bare
              ? BoxDecoration(
                  borderRadius: radius,
                  boxShadow: [if (widget.highlighted) ...glow(GlowColors.violet, intensity: 0.9)],
                )
              : BoxDecoration(
                  gradient: outgoing
                      ? GlowColors.outgoing
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.alphaBlend(GlowColors.cyan.withValues(alpha: 0.16), GlowColors.surface),
                            Color.alphaBlend(GlowColors.teal.withValues(alpha: 0.10), GlowColors.surface),
                          ],
                        ),
                  borderRadius: radius,
                  border: Border.all(
                    color: edgeColor,
                    width: delivery == Delivery.read || widget.highlighted ? 1.4 : 1,
                  ),
                  boxShadow: [
                    if (delivery == Delivery.read && outgoing) ...glow(GlowColors.cyan, intensity: 0.25),
                    if (widget.highlighted) ...glow(GlowColors.violet, intensity: 0.9),
                    if (bloom > 0) ...glow(GlowColors.amber, intensity: bloom),
                    if (dragGlow > 0)
                      ...glow(outgoing ? GlowColors.amber : GlowColors.cyan, intensity: dragGlow),
                  ],
                ),
          child: child,
        );
      },
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (senderName != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Text(
                  senderName,
                  style: TextStyle(
                    color: Display.accentFor(Display.senderId(m.senderId)),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            if (m.forwardInfo != null) _ForwardHeader(info: m.forwardInfo!, color: mutedColor),
            if (m.replyTo case td.MessageReplyToMessage(:final messageId, :final chatId, :final quote)
                when chatId == m.chatId || chatId == 0)
              _ReplyQuote(
                chatId: m.chatId,
                messageId: messageId,
                quote: quote?.isManual ?? false ? quote!.text.text : null,
                outgoing: outgoing,
                onTap: () => widget.onReplyQuoteTap(messageId),
              ),
            MessageContentView(
              messages: row.messages,
              textColor: textColor,
              mutedColor: mutedColor,
              outgoing: outgoing,
              footer: _Footer(
                message: m,
                delivery: delivery,
                outgoing: m.isOutgoing && !widget.isChannel,
                color: mutedColor,
              ),
              overlayFooter: _Footer(
                message: m,
                delivery: delivery,
                outgoing: m.isOutgoing && !widget.isChannel,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    final reactions = m.interactionInfo?.reactions?.reactions ?? const [];

    final content = Column(
      crossAxisAlignment: outgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        bubble,
        if (reactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ReactionsRow(reactions: reactions, onTap: widget.onReaction),
          ),
      ],
    );

    final showAvatar = widget.isGroup && !outgoing;
    final rowWidget = Padding(
      padding: EdgeInsets.only(left: 10, right: 10, top: row.firstInRun ? 8 : 2, bottom: 2),
      child: Row(
        mainAxisAlignment: outgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (widget.selecting)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 8),
              child: Icon(
                widget.selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: widget.selected ? GlowColors.violet : GlowColors.outlineStrong,
              ),
            ),
          if (showAvatar)
            SizedBox(
              width: 38,
              child: row.lastInRun ? _SenderAvatar(sender: m.senderId) : const SizedBox.shrink(),
            ),
          Flexible(child: content),
        ],
      ),
    );

    // Each direction runs its configured action; _drag is signed, positive
    // toward the right edge.
    final action = _drag >= 0 ? widget.swipeRight : widget.swipeLeft;
    final swipe = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        final box = _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
        if (widget.selecting || widget.onMenu == null || box == null) {
          widget.onTap();
        } else {
          widget.onMenu!(box.localToGlobal(Offset.zero) & box.size);
        }
      },
      onLongPress: widget.onLongPress,
      onHorizontalDragUpdate: widget.selecting
          ? null
          : (d) {
              const max = _replyThreshold * 1.4;
              final lo = widget.swipeLeft == MessageSwipe.none ? 0.0 : -max;
              final hi = widget.swipeRight == MessageSwipe.none ? 0.0 : max;
              setState(() => _drag = (_drag + d.delta.dx).clamp(lo, hi));
              final past = _drag.abs() >= _replyThreshold;
              if (!_crossed && past) {
                _crossed = true;
                HapticFeedback.selectionClick();
              } else if (_crossed && !past) {
                _crossed = false;
              }
            },
      onHorizontalDragEnd: widget.selecting
          ? null
          : (_) {
              if (_drag.abs() >= _replyThreshold) {
                widget.onSwipe(_drag > 0 ? SwipeSide.right : SwipeSide.left);
              }
              setState(() {
                _drag = 0;
                _crossed = false;
              });
            },
      child: AnimatedContainer(
        duration: _drag == 0 ? Motion.standard : Duration.zero,
        curve: Motion.move,
        transform: Matrix4.translationValues(_drag * 0.6, 0, 0),
        color: widget.selected ? GlowColors.violet.withValues(alpha: 0.12) : Colors.transparent,
        child: Stack(
          children: [
            rowWidget,
            if (_drag.abs() > 8)
              Positioned.fill(
                child: Align(
                  // The icon shows on the side the bubble moved away from.
                  alignment: _drag > 0 ? Alignment.centerLeft : Alignment.centerRight,
                  child: Opacity(
                    opacity: (_drag.abs() / _replyThreshold).clamp(0.0, 1.0),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: switch (action) {
                        MessageSwipe.reply => const Icon(Icons.reply_rounded, color: GlowColors.cyan),
                        MessageSwipe.react => Text(widget.swipeEmoji, style: const TextStyle(fontSize: 22)),
                        MessageSwipe.delete => const Icon(
                          Icons.delete_outline_rounded,
                          color: GlowColors.coral,
                        ),
                        MessageSwipe.none => const SizedBox.shrink(),
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Semantics(
      container: true,
      label: _semanticLabel(cache, m, delivery, outgoing),
      onLongPressHint: 'message actions',
      customSemanticsActions: {
        for (final (side, a) in [(SwipeSide.left, widget.swipeLeft), (SwipeSide.right, widget.swipeRight)])
          if (a != MessageSwipe.none)
            CustomSemanticsAction(
              label: switch (a) {
                MessageSwipe.reply => 'Reply',
                MessageSwipe.react => 'React ${widget.swipeEmoji}',
                MessageSwipe.delete => 'Delete',
                MessageSwipe.none => '',
              },
            ): () =>
                widget.onSwipe(side),
      },
      child: _animates
          ? FadeTransition(
              opacity: _entrance,
              child: SlideTransition(position: _slide, child: swipe),
            )
          : swipe,
    );
  }

  String _semanticLabel(TelegramCache cache, td.Message m, Delivery delivery, bool outgoing) {
    final who = outgoing ? 'You' : Display.senderName(cache, m.senderId);
    final time = _hm.format(Display.messageDate(m));
    final state = outgoing
        ? switch (delivery) {
            Delivery.read => ', read',
            Delivery.sent => ', sent',
            Delivery.pending => ', sending',
            Delivery.failed => ', failed to send',
          }
        : '';
    return '$who: ${Display.preview(cache, m)}, $time$state';
  }
}

class _SenderAvatar extends StatelessWidget {
  const _SenderAvatar({required this.sender});

  final td.MessageSender sender;

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    return switch (sender) {
      td.MessageSenderUser(:final userId) => ChatAvatar.user(cache.users[userId], size: 30),
      td.MessageSenderChat(:final chatId) =>
        cache.chats[chatId] != null
            ? ChatAvatar.chat(cache.chats[chatId]!, size: 30)
            : const SizedBox(width: 30),
    };
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.message, required this.delivery, required this.outgoing, required this.color});

  final td.Message message;
  final Delivery delivery;
  final bool outgoing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final time = _hm.format(Display.messageDate(message));
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.editDate != 0) Text('edited ', style: TextStyle(color: color, fontSize: 11)),
          if (message.interactionInfo != null &&
              message.interactionInfo!.viewCount > 0 &&
              message.isChannelPost) ...[
            Icon(Icons.visibility_outlined, size: 12, color: color),
            Text(
              ' ${_compact(message.interactionInfo!.viewCount)}  ',
              style: TextStyle(color: color, fontSize: 11),
            ),
          ],
          Text(time, style: TextStyle(color: color, fontSize: 11)),
          if (outgoing) ...[
            const SizedBox(width: 5),
            switch (delivery) {
              Delivery.pending => Icon(Icons.schedule_rounded, size: 12, color: color),
              Delivery.failed => const Icon(Icons.error_outline_rounded, size: 13, color: GlowColors.error),
              // Shape + colour change: ring when sent, filled dot when read.
              Delivery.sent => Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.3),
                ),
              ),
              Delivery.read => Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: GlowColors.onAccent),
              ),
            },
          ],
        ],
      ),
    );
  }

  static String _compact(int n) => n >= 1000000
      ? '${(n / 1000000).toStringAsFixed(1)}M'
      : n >= 1000
      ? '${(n / 1000).toStringAsFixed(1)}K'
      : '$n';
}

class _ForwardHeader extends StatelessWidget {
  const _ForwardHeader({required this.info, required this.color});

  final td.MessageForwardInfo info;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final from = switch (info.origin) {
      td.MessageOriginUser(:final senderUserId) => Display.userName(cache.users[senderUserId]),
      td.MessageOriginHiddenUser(:final senderName) => senderName,
      td.MessageOriginChat(:final senderChatId) => cache.chats[senderChatId]?.title ?? 'a chat',
      td.MessageOriginChannel(:final chatId) => cache.chats[chatId]?.title ?? 'a channel',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forward_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Forwarded from $from',
              style: TextStyle(color: color, fontSize: 12, fontStyle: FontStyle.italic),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Quote of the replied-to message; loads it lazily from TDLib's cache.
/// A passage the sender picked ([quote]) replaces the message preview.
class _ReplyQuote extends StatefulWidget {
  const _ReplyQuote({
    required this.chatId,
    required this.messageId,
    required this.outgoing,
    required this.onTap,
    this.quote,
  });

  final int chatId;
  final int messageId;
  final String? quote;
  final bool outgoing;
  final VoidCallback onTap;

  @override
  State<_ReplyQuote> createState() => _ReplyQuoteState();
}

class _ReplyQuoteState extends State<_ReplyQuote> {
  td.Message? _message;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.read<ConversationCubit>().messageById(widget.messageId).then((m) {
      if (mounted) setState(() => _message = m);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final m = _message;
    final accent = widget.outgoing ? GlowColors.onOutgoing : GlowColors.cyan;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              m == null ? 'Reply' : (m.isOutgoing ? 'You' : Display.senderName(cache, m.senderId)),
              style: TextStyle(color: accent, fontWeight: FontWeight.w600, fontSize: 12),
            ),
            if (widget.quote case final quote?)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      quote,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.outgoing ? GlowColors.onOutgoing : GlowColors.text,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  Icon(Icons.format_quote_rounded, size: 16, color: accent),
                ],
              )
            else
              Text(
                m == null ? '…' : Display.preview(cache, m),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.outgoing ? GlowColors.onOutgoing : GlowColors.textMuted,
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
