import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../../../core/telegram/display.dart';
import '../../../../../core/telegram/telegram_cache.dart';
import 'generic_content.dart';
import 'text_content.dart';

/// Content types rendered edge-to-edge (no text padding around them).
bool isMediaContent(td.MessageContent c) => switch (c) {
  td.MessagePhoto() || td.MessageVideo() || td.MessageAnimation() || td.MessageSticker() => true,
  td.MessageVideoNote() => true,
  _ => false,
};

/// Picks the renderer for a message's content. [messages] has more than one
/// entry for albums. [footer] (time, read state) is placed by the renderer.
class MessageContentView extends StatelessWidget {
  const MessageContentView({
    super.key,
    required this.messages,
    required this.textColor,
    required this.mutedColor,
    required this.outgoing,
    required this.footer,
  });

  final List<td.Message> messages;
  final Color textColor;
  final Color mutedColor;
  final bool outgoing;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final m = messages.last;
    return switch (m.content) {
      td.MessageText(:final text) => TextContent(text: text, color: textColor, footer: footer),
      td.MessageAnimatedEmoji(:final emoji) => BigEmojiContent(emoji: emoji, footer: footer),
      _ => GenericContent(
        icon: genericIcon(m.content),
        title: Display.preview(context.read<TelegramCache>(), m),
        color: textColor,
        mutedColor: mutedColor,
        footer: footer,
      ),
    };
  }
}
