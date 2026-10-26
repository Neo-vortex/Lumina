import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:lumina/features/proxy/data/proxy_config.dart';

void main() {
  test('parses MTProto share links (tg:// and t.me)', () {
    for (final link in [
      'tg://proxy?server=1.2.3.4&port=443&secret=ee00ff',
      'https://t.me/proxy?server=1.2.3.4&port=443&secret=ee00ff',
    ]) {
      final p = ProxyConfig.parseLink(link)!;
      expect(p.kind, ProxyKind.mtproto);
      expect(p.server, '1.2.3.4');
      expect(p.port, 443);
      expect(p.secret, 'ee00ff');
    }
  });

  test('parses SOCKS5 links with credentials', () {
    final p = ProxyConfig.parseLink('https://t.me/socks?server=proxy.example&port=1080&user=u&pass=p')!;
    expect(p.kind, ProxyKind.socks5);
    expect(p.username, 'u');
    expect(p.password, 'p');
    expect(p.toTd(), isA<td.ProxyTypeSocks5>());
  });

  test('rejects malformed links', () {
    expect(ProxyConfig.parseLink('tg://proxy?server=x&port=99999&secret=a'), isNull);
    expect(ProxyConfig.parseLink('hello'), isNull);
  });

  test('JSON never contains secrets', () {
    const p = ProxyConfig(server: 's', port: 1, kind: ProxyKind.http, username: 'u', password: 'hunter2');
    expect(p.toJson().values, isNot(contains('hunter2')));
    final back = ProxyConfig.fromJson(p.toJson(), password: 'hunter2');
    expect(back.password, 'hunter2');
    expect(back.kind, ProxyKind.http);
  });

  test('finds every proxy link in pasted text, skipping duplicates', () {
    const text = '''
Fresh proxies:
1) tg://proxy?server=a.example&port=443&secret=ee01
2) https://t.me/proxy?server=b.example&port=8443&secret=dd02.
3) https://t.me/socks?server=c.example&port=1080
again: tg://proxy?server=a.example&port=443&secret=ee01
not a proxy: https://t.me/durov
''';
    final found = ProxyConfig.parseLinks(text);
    expect(found.map((p) => p.server), ['a.example', 'b.example', 'c.example']);
    expect(found[1].port, 8443);
    expect(found[1].secret, 'dd02');
    expect(ProxyConfig.parseLinks('nothing here'), isEmpty);
  });
}
