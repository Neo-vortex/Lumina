import 'dart:async';
import 'dart:convert';

import 'package:handy_tdlib_next/api.dart' as td;

import '../../../core/storage/app_preferences.dart';
import '../../../core/storage/secure_store.dart';
import '../../../core/tdlib/td_client.dart';
import '../../../core/tdlib/td_errors.dart';
import 'proxy_config.dart';

/// A proxy TDLib knows about, with its id.
class SavedProxy {
  const SavedProxy(this.id, this.config, {this.lastUsed = 0});
  final int id;
  final ProxyConfig config;
  final int lastUsed;
}

/// TDLib's native proxy API (spec §5) plus our own encrypted copy.
///
/// TDLib stores proxies in its database, which logout and "reset local
/// data" delete. We keep non-secret fields in preferences and secrets in
/// Keystore storage, and re-add them whenever a fresh client reaches the
/// login screen, so a user behind a censor never loses access.
class ProxyRepository {
  ProxyRepository({required this._client, required this._prefs, required this._secure}) {
    _sub = _client.updates.listen((u) {
      if (u case td.UpdateAuthorizationState(
        authorizationState: td.AuthorizationStateWaitPhoneNumber() || td.AuthorizationStateReady(),
      )) {
        unawaited(restoreIfMissing());
      }
    });
  }

  final TdClient _client;
  final AppPreferences _prefs;
  final SecureStore _secure;
  StreamSubscription<td.Update>? _sub;

  Future<List<SavedProxy>> list() async {
    final result = await _client.invoke<td.Proxies>(const td.GetProxies());
    return [
      for (final p in result.proxies) SavedProxy(p.id, ProxyConfig.fromTd(p), lastUsed: p.lastUsedDate),
    ];
  }

  Future<SavedProxy> add(ProxyConfig c, {bool enable = true}) async {
    final p = await _client.invoke<td.Proxy>(
      td.AddProxy(server: c.server, port: c.port, enable: enable, type: c.toTd()),
    );
    await _persist();
    return SavedProxy(p.id, ProxyConfig.fromTd(p));
  }

  Future<void> edit(int id, ProxyConfig c) async {
    await _client.invoke<td.Proxy>(
      td.EditProxy(proxyId: id, server: c.server, port: c.port, enable: c.enabled, type: c.toTd()),
    );
    await _persist();
  }

  Future<void> enable(int id) async {
    await _client.invoke<td.Ok>(td.EnableProxy(proxyId: id));
    await _persist();
  }

  Future<void> disableAll() async {
    await _client.invoke<td.Ok>(const td.DisableProxy());
    await _persist();
  }

  Future<void> remove(int id) async {
    await _client.invoke<td.Ok>(td.RemoveProxy(proxyId: id));
    await _persist();
  }

  /// Round-trip time through the proxy, or the TDLib error.
  Future<Duration> ping(int id) async {
    final s = await _client.invoke<td.Seconds>(
      td.PingProxy(proxyId: id),
      timeout: const Duration(seconds: 20),
    );
    return Duration(microseconds: (s.seconds * 1e6).round());
  }

  /// Tests a configuration before saving it (no proxy id yet).
  Future<void> test(ProxyConfig c) => _client.invoke<td.Ok>(
    td.TestProxy(server: c.server, port: c.port, type: c.toTd(), dcId: 2, timeout: 10),
    timeout: const Duration(seconds: 20),
  );

  Future<String?> shareLink(int id) async {
    try {
      final url = await _client.invoke<td.HttpUrl>(td.GetProxyLink(proxyId: id));
      return url.url;
    } on TdException {
      return null;
    }
  }

  // ---- Persistence ----------------------------------------------------------

  Future<void> _persist() async {
    final current = await list();
    final json = [for (final p in current) p.config.toJson()];
    _prefs.proxiesJson = jsonEncode(json);
    for (final p in current) {
      await _secure.writeSecret(
        'proxy.${p.config.id}.password',
        p.config.password.isEmpty ? null : p.config.password,
      );
      await _secure.writeSecret(
        'proxy.${p.config.id}.secret',
        p.config.secret.isEmpty ? null : p.config.secret,
      );
    }
  }

  Future<List<ProxyConfig>> saved() async {
    final raw = jsonDecode(_prefs.proxiesJson) as List<dynamic>;
    final out = <ProxyConfig>[];
    for (final j in raw.cast<Map<String, dynamic>>()) {
      final base = ProxyConfig.fromJson(j);
      out.add(
        ProxyConfig.fromJson(
          j,
          password: await _secure.readSecret('proxy.${base.id}.password') ?? '',
          secret: await _secure.readSecret('proxy.${base.id}.secret') ?? '',
        ),
      );
    }
    return out;
  }

  var _restoring = false;

  /// Re-adds saved proxies to a TDLib instance that has none.
  Future<void> restoreIfMissing() async {
    if (_restoring) return;
    _restoring = true;
    try {
      final existing = await list();
      if (existing.isNotEmpty) return;
      for (final c in await saved()) {
        await _client.invoke<td.Proxy>(
          td.AddProxy(server: c.server, port: c.port, enable: c.enabled, type: c.toTd()),
        );
      }
    } on Exception {
      // Not ready yet; the next authorization update retries.
    } finally {
      _restoring = false;
    }
  }

  Future<void> dispose() async => _sub?.cancel();
}
