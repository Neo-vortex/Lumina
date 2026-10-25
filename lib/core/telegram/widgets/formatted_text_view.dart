import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../custom_emoji_store.dart';
import '../link_opener.dart';
import 'td_file_image.dart';

/// Renders TDLib [td.FormattedText] with all its entities:
/// * inline: bold, italic, underline, strikethrough, spoilers (tap to
///   reveal), monospace, links, mentions, hashtags, card numbers, media
///   timestamps and custom emoji;
/// * blocks: code blocks (language label, copy, horizontal scroll) and
///   quotes (expandable ones collapse to three lines).
///
/// Entity offsets are UTF-16 code units, which is also what Dart strings
/// index by.
class FormattedTextView extends StatefulWidget {
  const FormattedTextView(
    this.text, {
    super.key,
    this.style,
    this.linkColor,
    this.onMention,
    this.onMediaTimestamp,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  final td.FormattedText text;
  final TextStyle? style;
  final Color? linkColor;
  final void Function(String username)? onMention;

  /// Tapped "1:23"-style links that seek the replied-to media.
  final void Function(int seconds)? onMediaTimestamp;

  /// Applies to inline-only text (previews); block text is never clipped.
  final int? maxLines;
  final TextOverflow overflow;

  @override
  State<FormattedTextView> createState() => _FormattedTextViewState();
}

class _FormattedTextViewState extends State<FormattedTextView> {
  var _spoilersRevealed = false;
  final _expanded = <int>{};
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

  static bool _isBlock(td.TextEntityType t) =>
      t is td.TextEntityTypePre ||
      t is td.TextEntityTypePreCode ||
      t is td.TextEntityTypeBlockQuote ||
      t is td.TextEntityTypeExpandableBlockQuote;

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final base = widget.style ?? DefaultTextStyle.of(context).style;
    final link = widget.linkColor ?? Theme.of(context).colorScheme.secondary;
    final text = widget.text.text;

    // Top-level blocks, in order, ignoring blocks nested in other blocks.
    final blocks = <td.TextEntity>[];
    for (final e in [
      ...widget.text.entities.where((e) => _isBlock(e.type)),
    ]..sort((a, b) => a.offset.compareTo(b.offset))) {
      if (blocks.isEmpty || e.offset >= blocks.last.offset + blocks.last.length) blocks.add(e);
    }
    if (blocks.isEmpty) {
      return Text.rich(
        TextSpan(style: base, children: _spans(0, text.length, base, link)),
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }

    final children = <Widget>[];
    var p = 0;
    void paragraph(int start, int end) {
      // Blocks sit on their own lines; drop the newlines around them.
      while (start < end && text.codeUnitAt(start) == 10) {
        start++;
      }
      while (end > start && text.codeUnitAt(end - 1) == 10) {
        end--;
      }
      if (end > start) {
        children.add(Text.rich(TextSpan(style: base, children: _spans(start, end, base, link))));
      }
    }

    for (final b in blocks) {
      final start = b.offset.clamp(0, text.length), end = (b.offset + b.length).clamp(0, text.length);
      paragraph(p, start);
      children.add(switch (b.type) {
        td.TextEntityTypePre() || td.TextEntityTypePreCode() => _CodeBlock(
          code: text.substring(start, end),
          language: switch (b.type) {
            td.TextEntityTypePreCode(:final language) => language,
            _ => '',
          },
          style: base,
        ),
        _ => _Quote(
          color: link,
          expandable: b.type is td.TextEntityTypeExpandableBlockQuote,
          expanded: _expanded.contains(start),
          onToggle: () =>
              setState(() => _expanded.contains(start) ? _expanded.remove(start) : _expanded.add(start)),
          child: Text.rich(
            TextSpan(
              style: base,
              children: _spans(start, end, base, link, skip: b),
            ),
          ),
        ),
      });
      p = end;
    }
    paragraph(p, text.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: children,
    );
  }

  /// Styled spans for [start, end). [skip] is the enclosing block entity,
  /// already drawn by its container.
  List<InlineSpan> _spans(int start, int end, TextStyle base, Color link, {td.TextEntity? skip}) {
    final text = widget.text.text;
    final entities = widget.text.entities
        .where((e) => !identical(e, skip) && e.offset < end && e.offset + e.length > start)
        .toList();
    if (entities.isEmpty) return [TextSpan(text: text.substring(start, end))];

    // Split at every entity boundary, then style each piece by the entities
    // covering it (entities may nest).
    final cuts = <int>{start, end};
    for (final e in entities) {
      cuts
        ..add(e.offset.clamp(start, end))
        ..add((e.offset + e.length).clamp(start, end));
    }
    final points = cuts.toList()..sort();
    final spans = <InlineSpan>[];
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i], b = points[i + 1];
      if (a == b) continue;
      final piece = text.substring(a, b);
      final covering = entities.where((e) => e.offset <= a && e.offset + e.length >= b);
      var style = const TextStyle();
      GestureRecognizer? recognizer;
      var spoiler = false;
      int? customEmoji;
      String whole(td.TextEntity e) => text.substring(e.offset, (e.offset + e.length).clamp(0, text.length));
      for (final e in covering) {
        switch (e.type) {
          case td.TextEntityTypeBold():
            style = style.copyWith(fontWeight: FontWeight.w700);
          case td.TextEntityTypeItalic():
            style = style.copyWith(fontStyle: FontStyle.italic);
          case td.TextEntityTypeUnderline():
            style = style.copyWith(
              decoration: TextDecoration.combine([?style.decoration, TextDecoration.underline]),
            );
          case td.TextEntityTypeStrikethrough():
            style = style.copyWith(
              decoration: TextDecoration.combine([?style.decoration, TextDecoration.lineThrough]),
            );
          case td.TextEntityTypeCode() || td.TextEntityTypePre() || td.TextEntityTypePreCode():
            style = style.copyWith(
              fontFamily: 'monospace',
              backgroundColor: base.color?.withValues(alpha: 0.12),
            );
            recognizer ??= _tap(() => _copy(whole(e), 'Copied'));
          case td.TextEntityTypeBlockQuote() || td.TextEntityTypeExpandableBlockQuote():
            break;
          case td.TextEntityTypeSpoiler():
            spoiler = true;
          case td.TextEntityTypeTextUrl(:final url):
            style = style.copyWith(color: link, decoration: TextDecoration.underline);
            recognizer = _tap(() => openLink(context, url));
          case td.TextEntityTypeUrl():
            style = style.copyWith(color: link, decoration: TextDecoration.underline);
            final w = whole(e);
            recognizer = _tap(() => openLink(context, w.contains('://') ? w : 'https://$w'));
          case td.TextEntityTypeEmailAddress():
            style = style.copyWith(color: link);
            final w = whole(e);
            recognizer = _tap(() => openLink(context, 'mailto:$w'));
          case td.TextEntityTypePhoneNumber():
            style = style.copyWith(color: link);
            final w = whole(e);
            recognizer = _tap(() => openLink(context, 'tel:$w'));
          case td.TextEntityTypeBankCardNumber():
            style = style.copyWith(color: link);
            final w = whole(e);
            recognizer = _tap(() => _copy(w.replaceAll(' ', ''), 'Card number copied'));
          case td.TextEntityTypeMention():
            style = style.copyWith(color: link);
            final w = whole(e);
            if (widget.onMention != null) recognizer = _tap(() => widget.onMention!(w.substring(1)));
          case td.TextEntityTypeMediaTimestamp(:final mediaTimestamp):
            style = style.copyWith(color: link, decoration: TextDecoration.underline);
            if (widget.onMediaTimestamp != null) {
              recognizer = _tap(() => widget.onMediaTimestamp!(mediaTimestamp));
            }
          case td.TextEntityTypeHashtag() || td.TextEntityTypeCashtag() || td.TextEntityTypeBotCommand():
            style = style.copyWith(color: link);
          case td.TextEntityTypeMentionName():
            style = style.copyWith(color: link);
          case td.TextEntityTypeCustomEmoji(:final customEmojiId):
            customEmoji = customEmojiId;
        }
      }
      if (spoiler && !_spoilersRevealed) {
        spans.add(
          TextSpan(
            text: piece,
            style: style.copyWith(
              color: Colors.transparent,
              backgroundColor: base.color?.withValues(alpha: 0.35),
            ),
            recognizer: _tap(() => setState(() => _spoilersRevealed = true)),
          ),
        );
        continue;
      }
      if (customEmoji != null) {
        final size = (base.fontSize ?? 15) * 1.25;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _CustomEmoji(id: customEmoji, fallback: piece, size: size, style: base.merge(style)),
          ),
        );
        continue;
      }
      spans.add(TextSpan(text: piece, style: style, recognizer: recognizer));
    }
    return spans;
  }

  void _copy(String text, String toast) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(toast)));
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code, required this.language, required this.style});

  final String code;
  final String language;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final color = style.color ?? Colors.white;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  language.isEmpty ? 'code' : language,
                  style: style.copyWith(
                    fontSize: 11.5,
                    color: color.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Copy code',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                color: color.withValues(alpha: 0.7),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.maybeOf(context)
                      ?.showSnackBar(const SnackBar(content: Text('Code copied')));
                },
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: SelectableText(
              code,
              style: style.copyWith(
                fontFamily: 'monospace',
                fontSize: (style.fontSize ?? 15) * 0.88,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Quote extends StatelessWidget {
  const _Quote({
    required this.color,
    required this.child,
    required this.expandable,
    required this.expanded,
    required this.onToggle,
  });

  final Color color;
  final Widget child;
  final bool expandable;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final body = expandable && !expanded
        ? ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0, 0.6, 1],
            ).createShader(r),
            blendMode: BlendMode.dstIn,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 64),
              child: ClipRect(child: child),
            ),
          )
        : child;
    return GestureDetector(
      onTap: expandable ? onToggle : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(right: expandable ? 18 : 0),
              child: body,
            ),
            if (expandable)
              Positioned(
                right: 0,
                top: 0,
                child: Icon(
                  expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18,
                  color: color,
                  semanticLabel: expanded ? 'Collapse quote' : 'Expand quote',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A custom emoji as its static sticker image (WebP), or the animated
/// sticker's thumbnail; the plain emoji until it loads or if it can't.
class _CustomEmoji extends StatefulWidget {
  const _CustomEmoji({required this.id, required this.fallback, required this.size, required this.style});

  final int id;
  final String fallback;
  final double size;
  final TextStyle style;

  @override
  State<_CustomEmoji> createState() => _CustomEmojiState();
}

class _CustomEmojiState extends State<_CustomEmoji> {
  td.Sticker? _sticker;

  @override
  void initState() {
    super.initState();
    CustomEmojiStore? store;
    try {
      store = context.read<CustomEmojiStore>();
    } on ProviderNotFoundException {
      return;
    }
    _sticker = store.cached(widget.id);
    if (_sticker == null) {
      store.get(widget.id).then((s) {
        if (mounted && s != null) setState(() => _sticker = s);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _sticker;
    final file = switch (s?.format) {
      td.StickerFormatWebp() => s!.sticker,
      td.StickerFormatTgs() || td.StickerFormatWebm() => switch (s!.thumbnail) {
        td.Thumbnail(
          format: td.ThumbnailFormatWebp() || td.ThumbnailFormatPng() || td.ThumbnailFormatJpeg(),
          :final file,
        ) =>
          file,
        _ => null,
      },
      _ => null,
    };
    if (file == null) return Text(widget.fallback, style: widget.style);
    return Semantics(
      label: s!.emoji,
      child: SizedBox.square(
        dimension: widget.size,
        child: TdFileImage(file: file, fit: BoxFit.contain, priority: 4),
      ),
    );
  }
}
