import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:lumina/app/feature_wiring.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/proxy/data/proxy_config.dart';
import 'package:lumina/features/proxy/data/proxy_repository.dart';
import 'package:lumina/features/proxy/presentation/widgets/connection_settings.dart';

import '../../helpers/fakes.dart';

/// Answers GetProxies with [proxies] (FakeTdClient's built-in says none).
class ProxyClient extends FakeTdClient {
  List<td.AddedProxy> proxies = [];

  @override
  Future<T> invoke<T extends td.TdObject>(td.TdFunction function, {Duration? timeout}) async {
    if (function is td.GetProxies) return td.AddedProxies(proxies: proxies) as T;
    if (function is td.AddProxy) {
      final p = td.AddedProxy(
        id: proxies.length + 1,
        lastUsedDate: 0,
        isEnabled: function.enable,
        comment: function.comment,
        proxy: function.proxy,
      );
      proxies = [for (final o in proxies) function.enable ? o.copyWith(isEnabled: false) : o, p];
      return p as T;
    }
    return super.invoke(function, timeout: timeout);
  }
}

td.AddedProxy proxy(int id, td.ProxyType type, {bool enabled = true}) => td.AddedProxy(
  id: id,
  lastUsedDate: 0,
  isEnabled: enabled,
  comment: '',
  proxy: td.Proxy(server: 'proxy.example', port: 1080, type: type),
);

void main() {
  late ProxyClient client;
  late AppPreferences prefs;
  late ProxyRepository repo;

  setUp(() {
    client = ProxyClient();
    prefs = AppPreferences.inMemory();
    repo = ProxyRepository(client: client, prefs: prefs, secure: FakeSecureStore());
  });

  test('off by default: calls connect directly', () async {
    client.proxies = [proxy(1, const td.ProxyTypeSocks5(username: 'u', password: 'p'))];
    expect(await callProxyFor(repo), isNull);
  });

  test('on with an active SOCKS5 proxy: its address and credentials go to the engine', () async {
    prefs.callsUseProxy = true;
    client.proxies = [
      proxy(1, const td.ProxyTypeMtproto(secret: 'ab'), enabled: false),
      proxy(2, const td.ProxyTypeSocks5(username: 'u', password: 'p')),
    ];
    final p = (await callProxyFor(repo))!;
    expect((p.host, p.port, p.login, p.password), ('proxy.example', 1080, 'u', 'p'));
  });

  test('web proxies, which Lumina cannot edit, are left out of the list', () async {
    client.proxies = [
      proxy(1, const td.ProxyTypeWeb(path: '/p', secret: 's')),
      proxy(2, const td.ProxyTypeSocks5(username: 'u', password: 'p')),
    ];
    expect((await repo.list()).map((p) => p.id), [2]);
  });

  test('MTProto / HTTP proxies cannot carry calls', () async {
    prefs.callsUseProxy = true;
    client.proxies = [proxy(1, const td.ProxyTypeMtproto(secret: 'ab'))];
    expect(await callProxyFor(repo), isNull);
    final active = await repo.active();
    expect(ConnectionSettingsNotes.note(active, on: true), contains('only SOCKS5'));
  });

  test('adding a pasted list skips saved proxies and switches on a lone new one', () async {
    client.proxies = [proxy(1, const td.ProxyTypeMtproto(secret: 'ab'), enabled: false)];
    const saved = ProxyConfig(server: 'proxy.example', port: 1080, kind: ProxyKind.mtproto, secret: 'ab');
    const fresh = ProxyConfig(server: 'b.example', port: 443, kind: ProxyKind.mtproto, secret: 'cd');
    expect(await repo.addAll([saved, fresh]), 1);
    expect(client.proxies.last.isEnabled, isTrue);
    expect(repo.activeProxy.value?.server, 'b.example');

    const more = [
      ProxyConfig(server: 'c.example', port: 443, kind: ProxyKind.mtproto, secret: 'ef'),
      ProxyConfig(server: 'd.example', port: 1080, kind: ProxyKind.socks5),
    ];
    expect(await repo.addAll(more), 2);
    expect(client.proxies.where((p) => p.isEnabled).map((p) => p.proxy.server), ['b.example']);
  });
}
