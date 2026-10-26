import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../../core/telegram/widgets/animated_sticker.dart';
import '../../../../../core/storage/app_preferences.dart';
import '../../../../../core/tdlib/td_client.dart';
import '../link_preview_card.dart';

import '../../../../../core/telegram/widgets/formatted_text_view.dart';
import '../../../../../core/theme/glow_colors.dart';

/// Text with the footer tucked after the last line, like a caption, and
/// the link preview (if any) above or below it.
class TextContent extends StatelessWidget {
  const TextContent({
    super.key,
    required this.text,
    required this.color,
    required this.footer,
    this.linkPreview,
  });

  final td.FormattedText text;
  final Color color;
  final Widget footer;
  final td.LinkPreview? linkPreview;

  @override
  Widget build(BuildContext context) {
    final onAccent = color == GlowColors.onOutgoing;
    final linkColor = onAccent ? const Color(0xFFB9ECFF) : GlowColors.cyan;
    var showPreview = linkPreview != null;
    try {
      showPreview = showPreview && context.read<AppPreferences>().showLinkPreviews;
    } on ProviderNotFoundException {
      // Default on.
    }
    if (showPreview) {
      final card = LinkPreviewCard(preview: linkPreview!, textColor: color, accent: linkColor);
      final body = FormattedTextView(
        text,
        style: TextStyle(color: color, fontSize: 15.5, height: 1.35),
        linkColor: linkColor,
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            if (linkPreview!.showAboveText) card,
            body,
            if (!linkPreview!.showAboveText) card,
            Align(alignment: Alignment.centerRight, child: footer),
          ],
        ),
      );
    }
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
            linkColor: linkColor,
          ),
          Padding(padding: const EdgeInsets.only(bottom: 1), child: footer),
        ],
      ),
    );
  }
}

/// A lone emoji, shown large without a bubble feel.
/// A single emoji sent on its own: big, standing alone without a bubble.
/// Still until tapped, like Telegram: a tap plays it; tapping again also
/// plays Telegram's effect animation over it (and Telegram shows the other
/// side the interaction too).
class BigEmojiContent extends StatefulWidget {
  const BigEmojiContent({super.key, required this.emoji, required this.footer, this.sticker, this.message});

  final String emoji;
  final td.Sticker? sticker;
  final td.Message? message;
  final Widget footer;

  @override
  State<BigEmojiContent> createState() => _BigEmojiContentState();
}

class _BigEmojiContentState extends State<BigEmojiContent> {
  var _plays = 0;
  OverlayEntry? _effect;

  @override
  void dispose() {
    _effect?.remove();
    super.dispose();
  }

  Future<void> _tap() async {
    setState(() => _plays++);
    final m = widget.message;
    if (_plays < 2 || m == null) return;
    try {
      final effect = await context.read<TdClient>().invoke<td.Sticker>(
        td.ClickAnimatedEmojiMessage(chatId: m.chatId, messageId: m.id),
      );
      if (mounted) _showEffect(effect);
    } catch (_) {
      // No effect for this emoji; the emoji itself played.
    }
  }

  void _showEffect(td.Sticker effect) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final center = box.localToGlobal(box.size.center(Offset.zero));
    const size = 300.0;
    _effect?.remove();
    _effect = OverlayEntry(
      builder: (_) => Positioned(
        left: center.dx - size / 2,
        top: center.dy - size / 2,
        child: IgnorePointer(
          child: AnimatedSticker(key: const ValueKey('emoji-effect'), sticker: effect, size: size),
        ),
      ),
    );
    Overlay.of(context).insert(_effect!);
    Future<void>.delayed(const Duration(seconds: 3), () {
      _effect?.remove();
      _effect = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.sticker == null ? null : _tap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.sticker case final s?)
              AnimatedSticker(key: ValueKey(_plays), sticker: s, size: 140, autoplay: _plays > 0)
            else
              Text(widget.emoji, style: const TextStyle(fontSize: 52)),
            DecoratedBox(
              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: widget.footer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
