import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/gestures/swipe_actions.dart';
import '../../../../core/storage/app_preferences.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_sheet.dart';

/// Settings → Chats → Swipe gestures: what swiping left or right does on a
/// message and on a chat-list row, each card with a preview of both edges.
class SwipeSettingsScreen extends StatelessWidget {
  const SwipeSettingsScreen({super.key});

  static Route<void> route() => MaterialPageRoute(builder: (_) => const SwipeSettingsScreen());

  static const emojis = ['❤️', '👍', '🔥', '😂', '😮', '😢', '🙏', '👏', '🎉', '🤔', '👎', '💯'];

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<AppPreferences>();
    return Scaffold(
      appBar: AppBar(title: const Text('Gestures')),
      body: ListenableBuilder(
        listenable: prefs.changes,
        builder: (context, _) {
          final ml = prefs.messageSwipe(SwipeSide.left), mr = prefs.messageSwipe(SwipeSide.right);
          final cl = prefs.chatSwipe(SwipeSide.left), cr = prefs.chatSwipe(SwipeSide.right);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _Card(
                title: 'Messages',
                preview: _Preview(
                  left: _messageLook(mr, prefs.swipeEmoji),
                  right: _messageLook(ml, prefs.swipeEmoji),
                  sample: const _BubbleSample(),
                ),
                children: [
                  _DirectionTile(
                    key: const ValueKey('message-left'),
                    label: 'Swipe left',
                    look: _messageLook(ml, prefs.swipeEmoji),
                    onTap: () => _pickMessage(context, prefs, SwipeSide.left),
                  ),
                  _DirectionTile(
                    key: const ValueKey('message-right'),
                    label: 'Swipe right',
                    look: _messageLook(mr, prefs.swipeEmoji),
                    onTap: () => _pickMessage(context, prefs, SwipeSide.right),
                  ),
                  ListTile(
                    key: const ValueKey('swipe-emoji'),
                    leading: Text(prefs.swipeEmoji, style: const TextStyle(fontSize: 24)),
                    title: const Text('Reaction for "React"'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _pickEmoji(context, prefs),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Card(
                title: 'Double tap a message',
                preview: const SizedBox.shrink(),
                children: [
                  ListTile(
                    key: const ValueKey('double-tap'),
                    leading: _doubleTapLook(prefs.doubleTap, prefs.doubleTapEmoji).leading,
                    title: const Text('Action'),
                    subtitle: Text(_doubleTapLook(prefs.doubleTap, prefs.doubleTapEmoji).label),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      final v = await showGlowSheet<MessageDoubleTap>(
                        context,
                        title: 'Double tap a message',
                        builder: (context) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final a in MessageDoubleTap.values)
                              ListTile(
                                leading: _doubleTapLook(a, prefs.doubleTapEmoji).leading,
                                title: Text(_doubleTapLook(a, prefs.doubleTapEmoji).label),
                                trailing: a == prefs.doubleTap
                                    ? const Icon(Icons.check_rounded, color: GlowColors.violet)
                                    : null,
                                onTap: () => Navigator.pop(context, a),
                              ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      );
                      if (v != null) prefs.doubleTap = v;
                    },
                  ),
                  if (prefs.doubleTap == MessageDoubleTap.react)
                    ListTile(
                      key: const ValueKey('double-tap-emoji'),
                      leading: Text(prefs.doubleTapEmoji, style: const TextStyle(fontSize: 24)),
                      title: const Text('Reaction'),
                      subtitle: const Text('Any emoji the chat allows'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        final e = await _chooseEmoji(context, prefs.doubleTapEmoji, allowCustom: true);
                        if (e != null) prefs.doubleTapEmoji = e;
                      },
                    ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      'With an action set, a single tap waits a moment to tell taps apart. "Nothing" keeps it instant.',
                      style: TextStyle(color: GlowColors.textMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Card(
                title: 'Chat list',
                preview: _Preview(left: _chatLook(cr), right: _chatLook(cl), sample: const _ChatSample()),
                children: [
                  _DirectionTile(
                    key: const ValueKey('chat-left'),
                    label: 'Swipe left',
                    look: _chatLook(cl),
                    onTap: () => _pickChat(context, prefs, SwipeSide.left),
                  ),
                  _DirectionTile(
                    key: const ValueKey('chat-right'),
                    label: 'Swipe right',
                    look: _chatLook(cr),
                    onTap: () => _pickChat(context, prefs, SwipeSide.right),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 12, 8, 0),
                child: Text(
                  'Swipes that start at the very edge of the screen switch folders instead.',
                  style: TextStyle(color: GlowColors.textMuted, fontSize: 13),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickMessage(BuildContext context, AppPreferences prefs, SwipeSide side) async {
    final v = await _pick(context, side, [
      for (final a in MessageSwipe.values) (a, _messageLook(a, prefs.swipeEmoji)),
    ], prefs.messageSwipe(side));
    if (v != null) prefs.setMessageSwipe(side, v);
  }

  Future<void> _pickChat(BuildContext context, AppPreferences prefs, SwipeSide side) async {
    final v = await _pick(context, side, [
      for (final a in ChatSwipe.values) (a, _chatLook(a)),
    ], prefs.chatSwipe(side));
    if (v != null) prefs.setChatSwipe(side, v);
  }

  Future<T?> _pick<T>(BuildContext context, SwipeSide side, List<(T, _Look)> options, T current) =>
      showGlowSheet<T>(
        context,
        title: side == SwipeSide.left ? 'Swipe left' : 'Swipe right',
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (value, look) in options)
              ListTile(
                leading: look.leading,
                title: Text(look.label),
                trailing: value == current ? const Icon(Icons.check_rounded, color: GlowColors.violet) : null,
                onTap: () => Navigator.pop(context, value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );

  Future<void> _pickEmoji(BuildContext context, AppPreferences prefs) async {
    final e = await _chooseEmoji(context, prefs.swipeEmoji);
    if (e != null) prefs.swipeEmoji = e;
  }

  /// The common reactions, plus (with [allowCustom]) a field for any emoji.
  static Future<String?> _chooseEmoji(BuildContext context, String current, {bool allowCustom = false}) {
    final custom = TextEditingController();
    return showGlowSheet<String>(
      context,
      title: 'Reaction',
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in emojis)
                  InkResponse(
                    onTap: () => Navigator.pop(context, e),
                    radius: 30,
                    child: Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: e == current
                          ? BoxDecoration(
                              shape: BoxShape.circle,
                              color: GlowColors.violet.withValues(alpha: 0.2),
                            )
                          : null,
                      child: Text(e, style: const TextStyle(fontSize: 30)),
                    ),
                  ),
              ],
            ),
            if (allowCustom) ...[
              const SizedBox(height: 12),
              TextField(
                controller: custom,
                maxLength: 16,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26),
                decoration: const InputDecoration(hintText: 'Or type any emoji', counterText: ''),
                onSubmitted: (v) {
                  final e = v.characters.firstOrNull;
                  if (e != null) Navigator.pop(context, e);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Look {
  const _Look(this.label, this.leading, this.color);
  final String label;
  final Widget leading;
  final Color color;
}

_Look _messageLook(MessageSwipe a, String emoji) => switch (a) {
  MessageSwipe.reply => const _Look(
    'Reply',
    Icon(Icons.reply_rounded, color: GlowColors.cyan),
    GlowColors.cyan,
  ),
  MessageSwipe.react => _Look(
    'React with $emoji',
    Text(emoji, style: const TextStyle(fontSize: 22)),
    GlowColors.magenta,
  ),
  MessageSwipe.delete => const _Look(
    'Delete',
    Icon(Icons.delete_outline_rounded, color: GlowColors.coral),
    GlowColors.coral,
  ),
  MessageSwipe.none => const _Look(
    'Nothing',
    Icon(Icons.block_rounded, color: GlowColors.textMuted),
    Colors.transparent,
  ),
};

_Look _doubleTapLook(MessageDoubleTap a, String emoji) => switch (a) {
  MessageDoubleTap.react => _Look(
    'React with $emoji',
    Text(emoji, style: const TextStyle(fontSize: 22)),
    GlowColors.magenta,
  ),
  MessageDoubleTap.reply => const _Look(
    'Reply',
    Icon(Icons.reply_rounded, color: GlowColors.cyan),
    GlowColors.cyan,
  ),
  MessageDoubleTap.forward => const _Look(
    'Forward',
    Icon(Icons.shortcut_rounded, color: GlowColors.violet),
    GlowColors.violet,
  ),
  MessageDoubleTap.copy => const _Look(
    'Copy text',
    Icon(Icons.copy_rounded, color: GlowColors.teal),
    GlowColors.teal,
  ),
  MessageDoubleTap.select => const _Look(
    'Select',
    Icon(Icons.check_circle_outline_rounded, color: GlowColors.cyan),
    GlowColors.cyan,
  ),
  MessageDoubleTap.pin => const _Look(
    'Pin / unpin',
    Icon(Icons.push_pin_rounded, color: GlowColors.amber),
    GlowColors.amber,
  ),
  MessageDoubleTap.none => const _Look(
    'Nothing',
    Icon(Icons.block_rounded, color: GlowColors.textMuted),
    Colors.transparent,
  ),
};

_Look _chatLook(ChatSwipe a) => switch (a) {
  ChatSwipe.archive => const _Look(
    'Archive / unarchive',
    Icon(Icons.archive_rounded, color: GlowColors.cyan),
    GlowColors.cyan,
  ),
  ChatSwipe.pin => const _Look(
    'Pin / unpin',
    Icon(Icons.push_pin_rounded, color: GlowColors.violet),
    GlowColors.violet,
  ),
  ChatSwipe.mute => const _Look(
    'Mute / unmute',
    Icon(Icons.notifications_off_rounded, color: GlowColors.amber),
    GlowColors.amber,
  ),
  ChatSwipe.read => const _Look(
    'Mark read / unread',
    Icon(Icons.mark_chat_read_rounded, color: GlowColors.teal),
    GlowColors.teal,
  ),
  ChatSwipe.delete => const _Look(
    'Delete / leave',
    Icon(Icons.delete_outline_rounded, color: GlowColors.coral),
    GlowColors.coral,
  ),
  ChatSwipe.none => const _Look(
    'Nothing',
    Icon(Icons.block_rounded, color: GlowColors.textMuted),
    Colors.transparent,
  ),
};

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.preview, required this.children});

  final String title;
  final Widget preview;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: GlowColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: GlowColors.outline),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: GlowColors.violet,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
        preview,
        ...children,
      ],
    ),
  );
}

/// The sample row with each edge glowing in its action's colour. [left] is
/// revealed by swiping right (it shows on the left edge), and vice versa.
class _Preview extends StatelessWidget {
  const _Preview({required this.left, required this.right, required this.sample});

  final _Look left;
  final _Look right;
  final Widget sample;

  @override
  Widget build(BuildContext context) => Container(
    height: 76,
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: LinearGradient(
        colors: [
          left.color.withValues(alpha: 0.28),
          GlowColors.surfaceHigh,
          right.color.withValues(alpha: 0.28),
        ],
        stops: const [0, 0.5, 1],
      ),
    ),
    child: Row(
      children: [
        SizedBox(width: 48, child: Center(child: left.leading)),
        Expanded(child: sample),
        SizedBox(width: 48, child: Center(child: right.leading)),
      ],
    ),
  );
}

class _BubbleSample extends StatelessWidget {
  const _BubbleSample();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(gradient: GlowColors.outgoing, borderRadius: BorderRadius.circular(18)),
      child: const Text('See you at eight ✨', style: TextStyle(color: GlowColors.onOutgoing)),
    ),
  );
}

class _ChatSample extends StatelessWidget {
  const _ChatSample();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      CircleAvatar(radius: 18, backgroundColor: GlowColors.teal, child: Text('A')),
      SizedBox(width: 10),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ada', style: TextStyle(fontWeight: FontWeight.w600)),
            Text('See you at eight ✨', style: TextStyle(color: GlowColors.textMuted, fontSize: 13)),
          ],
        ),
      ),
    ],
  );
}

class _DirectionTile extends StatelessWidget {
  const _DirectionTile({super.key, required this.label, required this.look, required this.onTap});

  final String label;
  final _Look look;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(
      label.endsWith('left') ? Icons.west_rounded : Icons.east_rounded,
      color: GlowColors.textMuted,
    ),
    title: Text(label),
    subtitle: Text(look.label),
    trailing: look.leading,
    onTap: onTap,
  );
}
