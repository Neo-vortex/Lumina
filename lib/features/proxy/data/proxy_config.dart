import 'package:lumina_tdlib/api.dart' as td;

enum ProxyKind { socks5, http, mtproto }

/// A proxy as the user configured it. Secrets (password, MTProto secret)
/// are persisted separately in Keystore storage.
class ProxyConfig {
  const ProxyConfig({
    required this.server,
    required this.port,
    required this.kind,
    this.username = '',
    this.password = '',
    this.secret = '',
    this.httpOnly = false,
    this.enabled = false,
  });

  final String server;
  final int port;
  final ProxyKind kind;
  final String username;
  final String password;
  final String secret;
  final bool httpOnly;
  final bool enabled;

  String get id => '$server:$port:${kind.name}';

  td.ProxyType toTd() => switch (kind) {
    ProxyKind.socks5 => td.ProxyTypeSocks5(username: username, password: password),
    ProxyKind.http => td.ProxyTypeHttp(username: username, password: password, httpOnly: httpOnly),
    ProxyKind.mtproto => td.ProxyTypeMtproto(secret: secret),
  };

  td.Proxy toTdProxy() => td.Proxy(server: server, port: port, type: toTd());

  /// Null for proxy kinds Lumina can't edit (web proxies).
  static ProxyConfig? fromTd(td.AddedProxy added) {
    final p = added.proxy;
    return switch (p.type) {
      td.ProxyTypeSocks5(:final username, :final password) => ProxyConfig(
        server: p.server,
        port: p.port,
        kind: ProxyKind.socks5,
        username: username,
        password: password,
        enabled: added.isEnabled,
      ),
      td.ProxyTypeHttp(:final username, :final password, :final httpOnly) => ProxyConfig(
        server: p.server,
        port: p.port,
        kind: ProxyKind.http,
        username: username,
        password: password,
        httpOnly: httpOnly,
        enabled: added.isEnabled,
      ),
      td.ProxyTypeMtproto(:final secret) => ProxyConfig(
        server: p.server,
        port: p.port,
        kind: ProxyKind.mtproto,
        secret: secret,
        enabled: added.isEnabled,
      ),
      td.ProxyTypeWeb() => null,
    };
  }

  /// Non-secret fields only.
  Map<String, Object> toJson() => {
    'server': server,
    'port': port,
    'kind': kind.name,
    'username': username,
    'httpOnly': httpOnly,
    'enabled': enabled,
  };

  factory ProxyConfig.fromJson(Map<String, dynamic> j, {String password = '', String secret = ''}) =>
      ProxyConfig(
        server: j['server'] as String,
        port: j['port'] as int,
        kind: ProxyKind.values.byName(j['kind'] as String),
        username: j['username'] as String? ?? '',
        httpOnly: j['httpOnly'] as bool? ?? false,
        enabled: j['enabled'] as bool? ?? false,
        password: password,
        secret: secret,
      );

  ProxyConfig copyWith({bool? enabled}) => ProxyConfig(
    server: server,
    port: port,
    kind: kind,
    username: username,
    password: password,
    secret: secret,
    httpOnly: httpOnly,
    enabled: enabled ?? this.enabled,
  );

  static final _linkPattern = RegExp(
    r'(?:tg://(?:proxy|socks)|https?://(?:www\.)?(?:t\.me|telegram\.me|telegram\.dog)/(?:proxy|socks))'
    r'''\?[^\s<>"']+''',
    caseSensitive: false,
  );

  /// Sentence punctuation right after a link isn't part of it.
  static final _trailingPunctuation = RegExp(r'[.,;:!?)\]]+$');

  /// Every proxy link in [text] (a pasted list, a channel post, a QR code),
  /// in order and without duplicates.
  static List<ProxyConfig> parseLinks(String text) {
    final seen = <String>{};
    return [
      for (final m in _linkPattern.allMatches(text))
        if (parseLink(m[0]!.replaceFirst(_trailingPunctuation, '')) case final c?
            when seen.add('${c.id}:${c.secret}:${c.username}'))
          c,
    ];
  }

  /// Parses proxy share links:
  /// `tg://proxy?server=…&port=…&secret=…`, `https://t.me/proxy?…`,
  /// `tg://socks?server=…&port=…&user=…&pass=…`, `https://t.me/socks?…`.
  static ProxyConfig? parseLink(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null) return null;
    final q = uri.queryParameters;
    final server = q['server'];
    final port = int.tryParse(q['port'] ?? '');
    if (server == null || server.isEmpty || port == null || port <= 0 || port > 65535) return null;
    final path = '${uri.host}${uri.path}'.toLowerCase();
    if (path.contains('proxy') && q['secret'] != null) {
      return ProxyConfig(server: server, port: port, kind: ProxyKind.mtproto, secret: q['secret']!);
    }
    if (path.contains('socks')) {
      return ProxyConfig(
        server: server,
        port: port,
        kind: ProxyKind.socks5,
        username: q['user'] ?? '',
        password: q['pass'] ?? '',
      );
    }
    return null;
  }
}
