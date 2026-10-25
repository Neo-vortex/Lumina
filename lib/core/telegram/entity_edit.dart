import 'package:handy_tdlib_next/api.dart' as td;

/// Pure helpers for keeping [td.TextEntity] ranges right while text is
/// edited, trimmed or formatted. Offsets are UTF-16 units, like Dart.
abstract final class EntityEdit {
  /// Formatting the user may apply by hand (what TDLib accepts in input).
  static bool isManual(td.TextEntityType t) => switch (t) {
    td.TextEntityTypeBold() ||
    td.TextEntityTypeItalic() ||
    td.TextEntityTypeUnderline() ||
    td.TextEntityTypeStrikethrough() ||
    td.TextEntityTypeSpoiler() ||
    td.TextEntityTypeCode() ||
    td.TextEntityTypePre() ||
    td.TextEntityTypePreCode() ||
    td.TextEntityTypeBlockQuote() ||
    td.TextEntityTypeExpandableBlockQuote() ||
    td.TextEntityTypeTextUrl() ||
    td.TextEntityTypeMentionName() ||
    td.TextEntityTypeCustomEmoji() => true,
    _ => false,
  };

  static bool _same(td.TextEntityType a, td.TextEntityType b) => a.runtimeType == b.runtimeType;

  /// Moves entities after replacing [oldText] with [newText]: the changed
  /// region is found by common prefix/suffix. Entities inside a deleted
  /// region shrink; text typed at an entity's end extends it, like rich
  /// text editors do.
  static List<td.TextEntity> afterEdit(String oldText, String newText, List<td.TextEntity> entities) {
    if (entities.isEmpty || oldText == newText) return entities;
    var prefix = 0;
    final maxPrefix = oldText.length < newText.length ? oldText.length : newText.length;
    while (prefix < maxPrefix && oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < oldText.length - prefix &&
        suffix < newText.length - prefix &&
        oldText.codeUnitAt(oldText.length - 1 - suffix) == newText.codeUnitAt(newText.length - 1 - suffix)) {
      suffix++;
    }
    final removedEnd = oldText.length - suffix; // [prefix, removedEnd) replaced
    final inserted = newText.length - suffix - prefix;
    final delta = inserted - (removedEnd - prefix);
    // Positions before the edit stay; positions after it move by the length
    // change (so typing right before an entity leaves it out, and typing
    // right after its end extends it); positions inside the replaced text
    // collapse to the end of the new text.
    int map(int p) => p < prefix ? p : (p >= removedEnd ? p + delta : prefix + inserted);

    final out = <td.TextEntity>[];
    for (final e in entities) {
      final start = map(e.offset);
      final end = map(e.offset + e.length);
      if (end > start) out.add(td.TextEntity(offset: start, length: end - start, type: e.type));
    }
    return out;
  }

  /// Trims whitespace and moves entities to match.
  static td.FormattedText trim(String text, List<td.TextEntity> entities) {
    final lead = text.length - text.trimLeft().length;
    final trimmed = text.trim();
    final out = <td.TextEntity>[];
    for (final e in entities) {
      final start = (e.offset - lead).clamp(0, trimmed.length);
      final end = (e.offset + e.length - lead).clamp(0, trimmed.length);
      if (end > start) out.add(td.TextEntity(offset: start, length: end - start, type: e.type));
    }
    return td.FormattedText(text: trimmed, entities: out);
  }

  /// Whether [start, end) is entirely covered by entities of [type].
  static bool covers(List<td.TextEntity> entities, int start, int end, td.TextEntityType type) {
    if (end <= start) return false;
    var p = start;
    final same = entities.where((e) => _same(e.type, type)).toList()
      ..sort((a, b) => a.offset.compareTo(b.offset));
    for (final e in same) {
      if (e.offset <= p && e.offset + e.length > p) p = e.offset + e.length;
      if (p >= end) return true;
    }
    return false;
  }

  /// Applies [type] to [start, end), or removes it when already applied.
  /// Overlapping entities of the same kind are merged. Block-level kinds
  /// (code block, quote) replace each other.
  static List<td.TextEntity> toggle(
    List<td.TextEntity> entities,
    int start,
    int end,
    td.TextEntityType type,
  ) {
    if (end <= start) return entities;
    final remove = covers(entities, start, end, type);
    final out = <td.TextEntity>[];
    for (final e in entities) {
      final conflicting = _same(e.type, type) || (_isBlock(type) && _isBlock(e.type));
      final eEnd = e.offset + e.length;
      if (!conflicting || eEnd <= start || e.offset >= end) {
        out.add(e);
        continue;
      }
      // Keep the parts outside the selection.
      if (e.offset < start) out.add(td.TextEntity(offset: e.offset, length: start - e.offset, type: e.type));
      if (eEnd > end) out.add(td.TextEntity(offset: end, length: eEnd - end, type: e.type));
    }
    if (!remove) {
      var s = start, t = end;
      // Merge with touching runs of the same kind.
      out.removeWhere((e) {
        if (!_same(e.type, type) || e.type is td.TextEntityTypeTextUrl) return false;
        final eEnd = e.offset + e.length;
        if (eEnd < s || e.offset > t) return false;
        if (e.offset < s) s = e.offset;
        if (eEnd > t) t = eEnd;
        return true;
      });
      out.add(td.TextEntity(offset: s, length: t - s, type: type));
    }
    return out..sort((a, b) => a.offset.compareTo(b.offset));
  }

  static List<td.TextEntity> clear(List<td.TextEntity> entities, int start, int end) {
    final out = <td.TextEntity>[];
    for (final e in entities) {
      final eEnd = e.offset + e.length;
      if (eEnd <= start || e.offset >= end) {
        out.add(e);
        continue;
      }
      if (e.offset < start) out.add(td.TextEntity(offset: e.offset, length: start - e.offset, type: e.type));
      if (eEnd > end) out.add(td.TextEntity(offset: end, length: eEnd - end, type: e.type));
    }
    return out;
  }

  static bool _isBlock(td.TextEntityType t) =>
      t is td.TextEntityTypePre ||
      t is td.TextEntityTypePreCode ||
      t is td.TextEntityTypeBlockQuote ||
      t is td.TextEntityTypeExpandableBlockQuote;
}
