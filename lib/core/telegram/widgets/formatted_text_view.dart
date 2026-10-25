import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:handy_tdlib_next/api.dart' as td;
import 'package:url_launcher/url_launcher.dart';

/// Renders TDLib [td.FormattedText] with its entities: bold, italic,
/// underline, strikethrough, code/pre, spoilers (tap to reveal), links,
/// mentions, hashtags. Entity offsets are UTF-16 code units, which is also
/// what Dart strings index by.
class FormattedTextView extends StatefulWidget {
  const FormattedTextView(
    this.text, {
    super.key,
    this.style,
    this.linkColor,
    this.onMention,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  final td.FormattedText text;
  final TextStyle? style;
  final Color? linkColor;
  final void Function(String username)? onMention;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  State<FormattedTextView> createState() => _FormattedTextViewState();
}

class _FormattedTextViewState extends State<FormattedTextView> {
  var _spoilersRevealed = false;
  final _recognizers = <GestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final r = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(r);
    return r;
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final base = widget.style ?? DefaultTextStyle.of(context).style;
    final link = widget.linkColor ?? Theme.of(context).colorScheme.secondary;
    return Text.rich(
      TextSpan(style: base, children: _spans(base, link)),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }

  List<InlineSpan> _spans(TextStyle base, Color link) {
    final text = widget.text.text;
    if (widget.text.entities.isEmpty) return [TextSpan(text: text)];

    // Split at every entity boundary, then style each piece by the entities
    // covering it (entities may nest).
    final cuts = <int>{0, text.length};
    for (final e in widget.text.entities) {
      cuts
        ..add(e.offset.clamp(0, text.length))
        ..add((e.offset + e.length).clamp(0, text.length));
    }
    final points = cuts.toList()..sort();
    final spans = <InlineSpan>[];
    for (var i = 0; i < points.length - 1; i++) {
      final start = points[i], end = points[i + 1];
      if (start == end) continue;
      final piece = text.substring(start, end);
      final covering = widget.text.entities.where((e) => e.offset <= start && e.offset + e.length >= end);
      var style = const TextStyle();
      GestureRecognizer? recognizer;
      var spoiler = false;
      for (final e in covering) {
        switch (e.type) {
          case td.TextEntityTypeBold():
            style = style.copyWith(fontWeight: FontWeight.w700);
          case td.TextEntityTypeItalic():
            style = style.copyWith(fontStyle: FontStyle.italic);
          case td.TextEntityTypeUnderline():
            style = style.copyWith(decoration: TextDecoration.underline);
          case td.TextEntityTypeStrikethrough():
            style = style.copyWith(decoration: TextDecoration.lineThrough);
          case td.TextEntityTypeCode() || td.TextEntityTypePre() || td.TextEntityTypePreCode():
            style = style.copyWith(
              fontFamily: 'monospace',
              backgroundColor: base.color?.withValues(alpha: 0.12),
            );
            recognizer ??= _tap(() => Clipboard.setData(ClipboardData(text: piece)));
          case td.TextEntityTypeBlockQuote() || td.TextEntityTypeExpandableBlockQuote():
            style = style.copyWith(fontStyle: FontStyle.italic);
          case td.TextEntityTypeSpoiler():
            spoiler = true;
          case td.TextEntityTypeTextUrl(:final url):
            style = style.copyWith(color: link, decoration: TextDecoration.underline);
            recognizer = _tap(() => _open(url));
          case td.TextEntityTypeUrl():
            style = style.copyWith(color: link, decoration: TextDecoration.underline);
            final whole = text.substring(e.offset, (e.offset + e.length).clamp(0, text.length));
            recognizer = _tap(() => _open(whole.contains('://') ? whole : 'https://$whole'));
          case td.TextEntityTypeEmailAddress():
            style = style.copyWith(color: link);
            final whole = text.substring(e.offset, (e.offset + e.length).clamp(0, text.length));
            recognizer = _tap(() => _open('mailto:$whole'));
          case td.TextEntityTypePhoneNumber():
            style = style.copyWith(color: link);
            final whole = text.substring(e.offset, (e.offset + e.length).clamp(0, text.length));
            recognizer = _tap(() => _open('tel:$whole'));
          case td.TextEntityTypeMention():
            style = style.copyWith(color: link);
            final whole = text.substring(e.offset, (e.offset + e.length).clamp(0, text.length));
            if (widget.onMention != null) recognizer = _tap(() => widget.onMention!(whole.substring(1)));
          case td.TextEntityTypeHashtag() || td.TextEntityTypeCashtag() || td.TextEntityTypeBotCommand():
            style = style.copyWith(color: link);
          case td.TextEntityTypeMentionName():
            style = style.copyWith(color: link);
          default:
            break;
        }
      }
      if (spoiler && !_spoilersRevealed) {
        style = style.copyWith(
          color: Colors.transparent,
          backgroundColor: base.color?.withValues(alpha: 0.35),
        );
        recognizer = _tap(() => setState(() => _spoilersRevealed = true));
      }
      spans.add(TextSpan(text: piece, style: style, recognizer: recognizer));
    }
    return spans;
  }

  static Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
