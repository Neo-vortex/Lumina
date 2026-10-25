import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:lumina/app/feature_wiring.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/proxy/data/proxy_repository.dart';
import 'package:lumina/features/proxy/presentation/widgets/connection_settings.dart';

import '../../helpers/fakes.dart';

/// Answers GetProxies with [proxies] (FakeTdClient's built-in says none).
class ProxyClient extends FakeTdClient {
  List<td.AddedProxy> proxies = [];

  @override
  Future<T> invoke<T extends td.TdObject>(td.TdFunction function, {Duration? timeout}) async {
    if (function is td.GetProxies) return td.AddedProxies(proxies: proxies) as T;
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
}
