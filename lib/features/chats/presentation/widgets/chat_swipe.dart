import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/gestures/swipe_actions.dart';
import '../../../../core/storage/app_preferences.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';
import '../../data/chats_repository.dart';
import 'chat_actions_sheet.dart';

/// A chat-list row that runs the configured action when swiped left or
/// right (Settings → Swipe gestures). The action's icon and colour glow in
/// from the edge as the row moves, with a tick at the threshold.
class SwipeableChatRow extends StatefulWidget {
  const SwipeableChatRow({
    super.key,
    required this.chat,
    required this.child,
    this.list = const td.ChatListMain(),
  });

  final td.Chat chat;
  final td.ChatList list;
  final Widget child;

  @override
  State<SwipeableChatRow> createState() => _SwipeableChatRowState();
}

class _SwipeableChatRowState extends State<SwipeableChatRow> {
  static const _threshold = 72.0;
  double _drag = 0;
  bool _crossed = false;

  ChatSwipe _actionFor(SwipeSide side) => context.read<AppPreferences>().chatSwipe(side);

  Future<void> _run(ChatSwipe action) async {
    final repo = context.read<ChatsRepository>();
    final cache = context.read<TelegramCache>();
    final messenger = ScaffoldMessenger.of(context);
    final chat = cache.chats[widget.chat.id] ?? widget.chat;
    try {
      switch (action) {
        case ChatSwipe.pin:
          await repo.setPinned(
            chat.id,
            !(cache.positionIn(chat, widget.list)?.isPinned ?? false),
            list: widget.list,
          );
        case ChatSwipe.archive:
          await repo.setArchived(chat.id, widget.list is! td.ChatListArchive);
        case ChatSwipe.mute:
          await repo.setMuted(chat.id, !cache.isMuted(chat));
        case ChatSwipe.read:
          chat.unreadCount > 0 || chat.isMarkedAsUnread
              ? await repo.markRead(chat)
              : await repo.setMarkedUnread(chat.id, true);
        case ChatSwipe.delete:
          await confirmAndDeleteChat(context, chat);
        case ChatSwipe.none:
          break;
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  GestureDragUpdateCallback _onUpdate(ChatSwipe left, ChatSwipe right) => (d) {
    const max = _threshold * 1.5;
    final lo = left == ChatSwipe.none ? 0.0 : -max;
    final hi = right == ChatSwipe.none ? 0.0 : max;
    setState(() => _drag = (_drag + d.delta.dx).clamp(lo, hi));
    final past = _drag.abs() >= _threshold;
    if (past != _crossed) {
      _crossed = past;
      if (past) HapticFeedback.selectionClick();
    }
  };

  void _onEnd() {
    final side = _drag > 0 ? SwipeSide.right : SwipeSide.left;
    final fire = _drag.abs() >= _threshold;
    setState(() {
      _drag = 0;
      _crossed = false;
    });
    if (fire) _run(_actionFor(side));
  }

  @override
  Widget build(BuildContext context) {
    final left = _actionFor(SwipeSide.left), right = _actionFor(SwipeSide.right);
    final action = _drag >= 0 ? right : left;
    final (icon, color) = _look(action);
    final progress = (_drag.abs() / _threshold).clamp(0.0, 1.0);
    final width = MediaQuery.sizeOf(context).width;
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _MidRowDrag: GestureRecognizerFactoryWithHandlers<_MidRowDrag>(
          () => _MidRowDrag(screenWidth: width),
          (g) => g
            ..screenWidth = width
            ..onUpdate = _onUpdate(left, right)
            ..onEnd = (_) => _onEnd(),
        ),
      },
      child: Stack(
        children: [
          if (_drag != 0)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: _drag > 0 ? Alignment.centerLeft : Alignment.centerRight,
                    end: _drag > 0 ? Alignment.centerRight : Alignment.centerLeft,
                    colors: [
                      color.withValues(alpha: 0.35 * progress),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Align(
                  alignment: _drag > 0 ? Alignment.centerLeft : Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Transform.scale(
                      scale: 0.7 + 0.3 * progress,
                      child: Icon(icon, color: color.withValues(alpha: 0.4 + 0.6 * progress), size: 26),
                    ),
                  ),
                ),
              ),
            ),
          AnimatedContainer(
            duration: _drag == 0 ? Motion.standard : Duration.zero,
            curve: Motion.move,
            transform: Matrix4.translationValues(_drag, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }

  (IconData, Color) _look(ChatSwipe a) {
    final cache = context.read<TelegramCache>();
    final chat = cache.chats[widget.chat.id] ?? widget.chat;
    return switch (a) {
      ChatSwipe.pin => (
        cache.positionIn(chat, widget.list)?.isPinned ?? false
            ? Icons.push_pin_outlined
            : Icons.push_pin_rounded,
        GlowColors.violet,
      ),
      ChatSwipe.archive => (
        widget.list is td.ChatListArchive ? Icons.unarchive_rounded : Icons.archive_rounded,
        GlowColors.cyan,
      ),
      ChatSwipe.mute => (
        cache.isMuted(chat) ? Icons.notifications_rounded : Icons.notifications_off_rounded,
        GlowColors.amber,
      ),
      ChatSwipe.read => (Icons.mark_chat_read_rounded, GlowColors.teal),
      ChatSwipe.delete => (Icons.delete_outline_rounded, GlowColors.coral),
      ChatSwipe.none => (Icons.circle, Colors.transparent),
    };
  }
}

/// A horizontal drag that ignores touches starting near the screen edges,
/// so those still reach the folder pages behind the list.
class _MidRowDrag extends HorizontalDragGestureRecognizer {
  _MidRowDrag({required this.screenWidth});

  static const edge = 40.0;
  double screenWidth;

  @override
  bool isPointerAllowed(PointerEvent event) {
    final x = event.position.dx;
    return x > edge && x < screenWidth - edge && super.isPointerAllowed(event);
  }
}
