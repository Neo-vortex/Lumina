import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/tdlib/td_client.dart';
import '../../../../core/tdlib/td_errors.dart';
import '../../../../core/telegram/link_opener.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_sheet.dart';
import '../screens/conversation_screen.dart';

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

/// A bot's buttons under its message, as rows of glass pills.
class InlineKeyboard extends StatefulWidget {
  const InlineKeyboard({
    super.key,
    required this.message,
    required this.markup,
    required this.botUsername,
    required this.onSwitchInline,
  });

  final td.Message message;
  final td.ReplyMarkupInlineKeyboard markup;

  /// Who "switch inline" buttons address; empty when unknown.
  final String botUsername;

  /// Puts text into the composer.
  final ValueChanged<String> onSwitchInline;

  @override
  State<InlineKeyboard> createState() => _InlineKeyboardState();
}

class _InlineKeyboardState extends State<InlineKeyboard> {
  td.InlineKeyboardButton? _pending;

  Future<void> _press(td.InlineKeyboardButton b) async {
    switch (b.type) {
      case td.InlineKeyboardButtonTypeUrl(:final url) ||
          td.InlineKeyboardButtonTypeLoginUrl(:final url) ||
          td.InlineKeyboardButtonTypeWebApp(:final url):
        await openLink(context, url);
      case td.InlineKeyboardButtonTypeCallback(:final data):
        await _callback(b, data);
      case td.InlineKeyboardButtonTypeCopyText(:final text):
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) _snack(context, 'Copied');
      case td.InlineKeyboardButtonTypeUser(:final userId):
        await _openUser(userId);
      case td.InlineKeyboardButtonTypeSwitchInline(:final query):
        final bot = widget.botUsername;
        widget.onSwitchInline(bot.isEmpty ? query : '@$bot $query');
      default:
        _snack(context, 'Not supported yet');
    }
  }

  Future<void> _callback(td.InlineKeyboardButton b, String data) async {
    if (_pending != null) return;
    setState(() => _pending = b);
    try {
      final answer = await context.read<TdClient>().invoke<td.CallbackQueryAnswer>(
        td.GetCallbackQueryAnswer(
          chatId: widget.message.chatId,
          messageId: widget.message.id,
          payload: td.CallbackQueryPayloadData(data: data),
        ),
      );
      if (!mounted) return;
      setState(() => _pending = null);
      if (answer.url.isNotEmpty) {
        await openLink(context, answer.url);
      } else if (answer.text.isEmpty) {
        // The bot only acknowledged the press.
      } else if (answer.showAlert) {
        await showGlowSheet<void>(
          context,
          accent: GlowColors.cyan,
          builder: (_) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Text(answer.text, style: const TextStyle(fontSize: 16, height: 1.4)),
          ),
        );
      } else {
        _snack(context, answer.text);
      }
    } on TdException catch (e) {
      if (!mounted) return;
      setState(() => _pending = null);
      _snack(context, e.message);
    }
  }

  Future<void> _openUser(int userId) async {
    try {
      final chat = await context.read<TdClient>().invoke<td.Chat>(
        td.CreatePrivateChat(userId: userId, force: false),
      );
      if (mounted) await Navigator.of(context).push(ConversationScreen.route(chat.id));
    } on TdException catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final row in widget.markup.rows)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              for (final (i, b) in row.indexed) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: _Pill(button: b, pending: identical(_pending, b), onTap: () => _press(b)),
                ),
              ],
            ],
          ),
        ),
    ],
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.button, required this.pending, required this.onTap});

  final td.InlineKeyboardButton button;
  final bool pending;
  final VoidCallback onTap;

  IconData? get _icon => switch (button.type) {
    td.InlineKeyboardButtonTypeUrl() || td.InlineKeyboardButtonTypeLoginUrl() => Icons.north_east_rounded,
    td.InlineKeyboardButtonTypeWebApp() => Icons.open_in_new_rounded,
    td.InlineKeyboardButtonTypeCopyText() => Icons.copy_rounded,
    td.InlineKeyboardButtonTypeSwitchInline() => Icons.reply_rounded,
    _ => null,
  };

  Color get _accent => switch (button.style) {
    td.ButtonStylePrimary() => GlowColors.violet,
    td.ButtonStyleDanger() => GlowColors.error,
    td.ButtonStyleSuccess() => GlowColors.teal,
    _ => GlowColors.cyan,
  };

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    final icon = _icon;
    return Material(
      color: Color.alphaBlend(accent.withValues(alpha: 0.12), GlowColors.surface.withValues(alpha: 0.85)),
      shape: StadiumBorder(side: BorderSide(color: accent.withValues(alpha: 0.45))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: pending ? null : onTap,
        splashColor: accent.withValues(alpha: 0.2),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 38),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  button.text,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: pending ? Colors.transparent : GlowColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (pending)
                  SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                  ),
                if (icon != null && !pending)
                  Positioned(right: -4, top: 0, child: Icon(icon, size: 12, color: accent)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
