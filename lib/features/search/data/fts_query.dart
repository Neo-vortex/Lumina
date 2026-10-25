/// Turns what the user typed into FTS5 MATCH expressions.
///
/// * Terms of 3+ characters go to the trigram index as quoted phrases:
///   exact, case-insensitive substring matching in any script (CJK, Thai…
///   have no word boundaries, which is where Telegram's own search is weak).
/// * Shorter terms go to the word index as prefixes (`"ab"*`).
class FtsQuery {
  const FtsQuery({this.trigram, this.words});

  /// MATCH expression for the trigram table, or null.
  final String? trigram;

  /// MATCH expression for the unicode61 table, or null.
  final String? words;

  bool get isEmpty => trigram == null && words == null;

  static FtsQuery parse(String input) {
    final terms = input
        .trim()
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll(RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true), ''))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return const FtsQuery();
    final long = terms.where((t) => t.runes.length >= 3).toList();
    final short = terms.where((t) => t.runes.length < 3).toList();
    return FtsQuery(
      trigram: long.isEmpty ? null : long.map(_quote).join(' AND '),
      words: short.isEmpty ? null : short.map((t) => '${_quote(t)}*').join(' AND '),
    );
  }

  static String _quote(String t) => '"${t.replaceAll('"', '""')}"';
}
