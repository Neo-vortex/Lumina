import 'package:flutter/material.dart';

import '../theme/glow_colors.dart';

/// Renders a search snippet whose matches are wrapped in `[[` `]]`.
class HighlightedSnippet extends StatelessWidget {
  const HighlightedSnippet({super.key, required this.text, this.maxLines = 2});

  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    const hl = TextStyle(color: GlowColors.amber, fontWeight: FontWeight.w700);
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in RegExp(r'\[\[(.*?)\]\]', dotAll: true).allMatches(text)) {
      spans
        ..add(TextSpan(text: text.substring(last, m.start)))
        ..add(TextSpan(text: m.group(1), style: hl));
      last = m.end;
    }
    spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
