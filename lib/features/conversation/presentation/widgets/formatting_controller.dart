import 'package:flutter/material.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/entity_edit.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_button.dart';
import '../../../../core/widgets/glow_sheet.dart';

/// Composer text plus the formatting the user applied by hand (selection
/// menu → Bold, Code block, Quote, Link…). Entity ranges follow edits, and
/// the text field shows the formatting live.
class FormattingController extends TextEditingController {
  FormattingController({super.text});

  List<td.TextEntity> _entities = const [];
  List<td.TextEntity> get entities => _entities;

  td.FormattedText get formatted => td.FormattedText(text: text, entities: _entities);

  /// Loads a draft or a message being edited, keeping its formatting.
  void setFormatted(td.FormattedText t) {
    _entities = const [];
    value = TextEditingValue(
      text: t.text,
      selection: TextSelection.collapsed(offset: t.text.length),
    );
    _entities = [
      for (final e in t.entities)
        if (EntityEdit.isManual(e.type)) e,
    ];
    notifyListeners();
  }

  @override
  set value(TextEditingValue v) {
    if (v.text != text) _entities = EntityEdit.afterEdit(text, v.text, _entities);
    super.value = v;
  }

  @override
  void clear() {
    _entities = const [];
    super.clear();
  }

  bool get hasSelection => selection.isValid && !selection.isCollapsed;

  bool isApplied(td.TextEntityType type) =>
      hasSelection && EntityEdit.covers(_entities, selection.start, selection.end, type);

  void toggle(td.TextEntityType type) {
    if (!hasSelection) return;
    _entities = EntityEdit.toggle(_entities, selection.start, selection.end, type);
    notifyListeners();
  }

  void clearFormatting() {
    if (!hasSelection) return;
    _entities = EntityEdit.clear(_entities, selection.start, selection.end);
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (_entities.isEmpty) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final t = text;
    final cuts = <int>{0, t.length};
    for (final e in _entities) {
      cuts
        ..add(e.offset.clamp(0, t.length))
        ..add((e.offset + e.length).clamp(0, t.length));
    }
    final points = cuts.toList()..sort();
    final children = <TextSpan>[];
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i], b = points[i + 1];
      if (a == b) continue;
      var s = const TextStyle();
      final decorations = <TextDecoration>[];
      for (final e in _entities.where((e) => e.offset <= a && e.offset + e.length >= b)) {
        switch (e.type) {
          case td.TextEntityTypeBold():
            s = s.copyWith(fontWeight: FontWeight.w700);
          case td.TextEntityTypeItalic():
            s = s.copyWith(fontStyle: FontStyle.italic);
          case td.TextEntityTypeUnderline():
            decorations.add(TextDecoration.underline);
          case td.TextEntityTypeStrikethrough():
            decorations.add(TextDecoration.lineThrough);
          case td.TextEntityTypeSpoiler():
            s = s.copyWith(backgroundColor: GlowColors.textMuted.withValues(alpha: 0.35));
          case td.TextEntityTypeCode() || td.TextEntityTypePre() || td.TextEntityTypePreCode():
            s = s.copyWith(fontFamily: 'monospace', backgroundColor: GlowColors.surfaceHigh);
          case td.TextEntityTypeBlockQuote() || td.TextEntityTypeExpandableBlockQuote():
            s = s.copyWith(color: GlowColors.violet, fontStyle: FontStyle.italic);
          case td.TextEntityTypeTextUrl():
            s = s.copyWith(color: GlowColors.cyan);
            decorations.add(TextDecoration.underline);
          default:
            break;
        }
      }
      if (decorations.isNotEmpty) s = s.copyWith(decoration: TextDecoration.combine(decorations));
      children.add(TextSpan(text: t.substring(a, b), style: s));
    }
    return TextSpan(style: style, children: children);
  }
}

/// The formatting entries added to the composer's selection menu.
/// Asks for a URL in a glow sheet and links the selection to it.
Future<void> promptFormattingLink(BuildContext context, FormattingController c) async {
  final ctrl = TextEditingController(text: 'https://');
  final url = await showGlowSheet<String>(
    context,
    title: 'Add link',
    accent: GlowColors.cyan,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.link_rounded)),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
          const SizedBox(height: 16),
          GlowButton(label: 'Add link', onPressed: () => Navigator.pop(context, ctrl.text.trim())),
        ],
      ),
    ),
  );
  ctrl.dispose();
  if (url == null || url.isEmpty || url == 'https://') return;
  c.toggle(
    td.TextEntityTypeTextUrl(url: url.contains('://') || url.startsWith('tg:') ? url : 'https://$url'),
  );
}
