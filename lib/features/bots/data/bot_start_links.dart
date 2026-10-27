import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/tdlib/td_client.dart';
import '../../../core/tdlib/td_errors.dart';

/// `t.me/<bot>?start=<parameter>` deep links: the parameter waits here for
/// the bot chat's Start button.
class BotStartLinks {
  BotStartLinks(this._client);

  final TdClient _client;
  final _pending = <int, String>{};

  static ({String username, String parameter})? parse(Uri uri) {
    final start = uri.queryParameters['start'];
    if (start == null) return null;
    if (uri.scheme == 'tg' && uri.host == 'resolve') {
      final domain = uri.queryParameters['domain'];
      return domain == null || domain.isEmpty ? null : (username: domain, parameter: start);
    }
    final host = uri.host.toLowerCase();
    if (host != 't.me' && host != 'telegram.me') return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length != 1) return null;
    return (username: segments.single, parameter: start);
  }

  /// The chat [uri] points at, or null when it can't be found. For a bot the
  /// parameter is then pending for its Start; other chats just open.
  Future<int?> resolve(Uri uri) async {
    final link = parse(uri);
    if (link == null) return null;
    try {
      final chat = await _client.invoke<td.Chat>(td.SearchPublicChat(username: link.username));
      if (chat.type case td.ChatTypePrivate(:final userId)) {
        final user = await _client.invoke<td.User>(td.GetUser(userId: userId));
        if (user.type is td.UserTypeBot) _pending[chat.id] = link.parameter;
      }
      return chat.id;
    } on TdException {
      return null;
    }
  }

  String? peek(int chatId) => _pending[chatId];

  String? take(int chatId) => _pending.remove(chatId);
}
