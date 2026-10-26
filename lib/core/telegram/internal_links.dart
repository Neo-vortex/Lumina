import 'package:flutter/widgets.dart';

/// One kind of link Lumina opens itself instead of a browser
/// (t.me/addlist, proxy links, …). Registered by the composition root.
class InternalLinkHandler {
  const InternalLinkHandler({required this.matches, required this.open});

  final bool Function(Uri uri) matches;
  final Future<void> Function(BuildContext context, Uri uri) open;
}

/// The in-app link handlers. [openLink] and links from other apps ask this
/// first; anything unhandled goes to the browser as before.
class InternalLinks {
  InternalLinks([this._handlers = const []]);

  final List<InternalLinkHandler> _handlers;

  /// `t.me/x` without a scheme becomes `https://t.me/x`.
  static Uri? parse(String url) {
    final s = url.trim();
    if (s.isEmpty) return null;
    return Uri.tryParse(s.contains('://') ? s : 'https://$s');
  }

  bool canOpen(String url) {
    final uri = parse(url);
    return uri != null && _handlers.any((h) => h.matches(uri));
  }

  Future<bool> tryOpen(BuildContext context, String url) async {
    final uri = parse(url);
    if (uri == null) return false;
    for (final h in _handlers) {
      if (h.matches(uri)) {
        await h.open(context, uri);
        return true;
      }
    }
    return false;
  }
}
