final _pattern = RegExp(
  r'(?:(?:https?://)?(?:www\.)?(?:t\.me|telegram\.me|telegram\.dog)/addlist/|tg:(?://)?addlist\?slug=)'
  r'([A-Za-z0-9_-]+)',
  caseSensitive: false,
);

/// The invite slug of a chat-folder link, or null.
String? addlistSlug(String input) {
  final m = _pattern.firstMatch(input.trim());
  return m == null ? null : m[1];
}

/// TDLib accepts the https form for every link variant.
String addlistUrl(String slug) => 'https://t.me/addlist/$slug';

/// Every folder link in [text], canonical and without duplicates. The slug
/// alphabet has no punctuation, so a trailing "." or "!" is never included.
List<String> findAddlistLinks(String text) =>
    {for (final m in _pattern.allMatches(text)) addlistUrl(m[1]!)}.toList();
