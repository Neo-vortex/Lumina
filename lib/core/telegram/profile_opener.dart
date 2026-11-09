import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// Opens what an @username, a name mention or a t.me/username link points
/// at: a person's full profile (message, call, photos…), a group, channel
/// or bot's chat, or your own account. Provided by the composition root so
/// any text in the app can use it without plumbing callbacks.
class ProfileOpener {
  const ProfileOpener({required this.openUser, required this.openUsername});

  final Future<void> Function(BuildContext context, int userId) openUser;
  final Future<void> Function(BuildContext context, String username) openUsername;

  static ProfileOpener? maybeOf(BuildContext context) {
    try {
      return context.read<ProfileOpener>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// Paths on t.me that aren't usernames.
  static const _reserved = {
    'addlist', 'proxy', 'socks', 'joinchat', 'share', 'login', 'addstickers', 'addemoji', 'addtheme', //
    'setlanguage', 'confirmphone', 'invoice', 'giftcode', 'boost', 'contact', 'iv', 'bg', 'm', 'c', 's',
  };

  static final _username = RegExp(r'^[A-Za-z][A-Za-z0-9_]{3,31}$');

  /// The username a plain profile link names: `t.me/name`, `@name`-less
  /// `telegram.me/name`, `name.t.me` or `tg://resolve?domain=name`. Links
  /// with a start parameter, a post id or anything else return null.
  static String? usernameOf(Uri uri) {
    if (uri.queryParameters.containsKey('start') || uri.queryParameters.containsKey('startgroup'))
      return null;
    if (uri.scheme == 'tg') {
      if (uri.host != 'resolve') return null;
      final params = uri.queryParameters.keys.toSet()..remove('domain');
      final d = uri.queryParameters['domain'];
      return params.isEmpty && d != null && _username.hasMatch(d) ? d : null;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (host.endsWith('.t.me') && segments.isEmpty) {
      final sub = host.substring(0, host.length - 5);
      return _username.hasMatch(sub) && !_reserved.contains(sub) ? sub : null;
    }
    if (host != 't.me' && host != 'telegram.me' && host != 'www.t.me') return null;
    if (segments.length != 1 || uri.hasQuery) return null;
    final name = segments.single;
    return _username.hasMatch(name) && !_reserved.contains(name.toLowerCase()) ? name : null;
  }
}
