import 'package:flutter/material.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../../../core/telegram/widgets/formatted_text_view.dart';
import '../../../../../core/theme/glow_colors.dart';

/// Text with the footer tucked after the last line, like a caption.
class TextContent extends StatelessWidget {
  const TextContent({super.key, required this.text, required this.color, required this.footer});

  final td.FormattedText text;
  final Color color;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final onAccent = color == GlowColors.onAccent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 8,
        runSpacing: 2,
        children: [
          FormattedTextView(
            text,
            style: TextStyle(color: color, fontSize: 15.5, height: 1.35),
            linkColor: onAccent ? const Color(0xFF3B1C7A) : GlowColors.cyan,
          ),
          Padding(padding: const EdgeInsets.only(bottom: 1), child: footer),
        ],
      ),
    );
  }
}

/// A lone emoji, shown large without a bubble feel.
class BigEmojiContent extends StatelessWidget {
  const BigEmojiContent({super.key, required this.emoji, required this.footer});

  final String emoji;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 52)),
          footer,
        ],
      ),
    );
  }
}
