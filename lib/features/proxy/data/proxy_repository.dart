import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:lumina_tdlib/api.dart' as td;

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
        unawaited(restoreIfMissing().then((_) => _refreshActive()));
      }
    });
  }

  final _active = ValueNotifier<ProxyConfig?>(null);

  /// The proxy in use, kept current as proxies are added, switched or removed.
  ValueListenable<ProxyConfig?> get activeProxy => _active;

  Future<void> _refreshActive([List<SavedProxy>? current]) async {
    try {
      current ??= await list();
      _active.value = current.where((p) => p.config.enabled).firstOrNull?.config;
    } on Exception {
      // TDLib not ready; the next authorization update refreshes.
    }
  }

  final TdClient _client;
  final AppPreferences _prefs;
  final SecureStore _secure;
  StreamSubscription<td.Update>? _sub;

  Future<List<SavedProxy>> list() async {
    final result = await _client.invoke<td.AddedProxies>(const td.GetProxies());
    return [
      for (final p in result.proxies)
        if (ProxyConfig.fromTd(p) case final config?) SavedProxy(p.id, config, lastUsed: p.lastUsedDate),
    ];
  }

  /// The proxy TDLib uses right now, if any.
  Future<SavedProxy?> active() async {
    for (final p in await list()) {
      if (p.config.enabled) return p;
    }
    return null;
  }

  /// The SOCKS5 proxy calls may use ("Use proxy for calls"), or null when
  /// the setting is off or the active proxy can't carry calls (MTProto and
  /// HTTP proxies only tunnel Telegram's own protocol).
  Future<ProxyConfig?> callProxy() async {
    if (!_prefs.callsUseProxy) return null;
    final p = await active();
    return p != null && p.config.kind == ProxyKind.socks5 ? p.config : null;
  }

  Future<SavedProxy> add(ProxyConfig c, {bool enable = true}) async {
    final p = await _client.invoke<td.AddedProxy>(
      td.AddProxy(proxy: c.toTdProxy(), enable: enable, comment: ''),
    );
    await _persist();
    return SavedProxy(p.id, ProxyConfig.fromTd(p)!);
  }

  /// Adds the proxies not saved yet (from a pasted list or a QR code) and
  /// returns how many were new. A single new proxy is switched on, as with
  /// a tapped proxy link; several are left off for the user to pick.
  Future<int> addAll(List<ProxyConfig> configs) async {
    final existing = {for (final p in await list()) _key(p.config)};
    final fresh = [
      for (final c in configs)
        if (existing.add(_key(c))) c,
    ];
    for (final c in fresh) {
      await _client.invoke<td.AddedProxy>(
        td.AddProxy(proxy: c.toTdProxy(), enable: fresh.length == 1, comment: ''),
      );
    }
    if (fresh.isNotEmpty) await _persist();
    return fresh.length;
  }

  static String _key(ProxyConfig c) => '${c.id}:${c.secret}:${c.username}';

  Future<void> edit(int id, ProxyConfig c) async {
    await _client.invoke<td.AddedProxy>(
      td.EditProxy(proxyId: id, proxy: c.toTdProxy(), enable: c.enabled, comment: ''),
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
    final saved = (await list()).firstWhere((p) => p.id == id);
    final s = await _client.invoke<td.Seconds>(
      td.PingProxy(proxy: saved.config.toTdProxy()),
      timeout: const Duration(seconds: 20),
    );
    return Duration(microseconds: (s.seconds * 1e6).round());
  }

  /// Tests a configuration before saving it (no proxy id yet).
  Future<void> test(ProxyConfig c) => _client.invoke<td.Ok>(
    td.TestProxy(proxy: c.toTdProxy(), dcId: 2, timeout: 10),
    timeout: const Duration(seconds: 20),
  );

  Future<String?> shareLink(int id) async {
    try {
      final saved = (await list()).firstWhere((p) => p.id == id);
      final url = await _client.invoke<td.HttpUrl>(
        td.GetInternalLink(type: td.InternalLinkTypeProxy(proxy: saved.config.toTdProxy()), isHttp: true),
      );
      return url.url;
    } on TdException {
      return null;
    } on StateError {
      return null;
    }
  }

  // ---- Persistence ----------------------------------------------------------

  Future<void> _persist() async {
    final current = await list();
    await _refreshActive(current);
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
        await _client.invoke<td.AddedProxy>(
          td.AddProxy(proxy: c.toTdProxy(), enable: c.enabled, comment: ''),
        );
      }
    } on Exception {
      // Not ready yet; the next authorization update retries.
    } finally {
      _restoring = false;
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _active.dispose();
  }
}
