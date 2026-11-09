import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/accounts/account_store.dart';
import '../../../core/custom_server/custom_server.dart';
import '../../../core/storage/secure_store.dart';
import '../../../core/tdlib/td_paths.dart';

/// Where backups go: a NeoMtProto HTTP API's open (debug) backups, which
/// need no account. The device token from the first upload lets this phone
/// overwrite its own backups later.
class BackupConfig {
  const BackupConfig({required this.endpoint, this.deviceToken, this.auto = true});

  final Uri endpoint;
  final String? deviceToken;
  final bool auto;

  BackupConfig copyWith({bool? auto, String? deviceToken}) =>
      BackupConfig(endpoint: endpoint, deviceToken: deviceToken ?? this.deviceToken, auto: auto ?? this.auto);

  Map<String, Object?> toJson() => {'endpoint': '$endpoint', 'device_token': deviceToken, 'auto': auto};

  static BackupConfig? fromJson(Object? j) {
    if (j is! Map) return null;
    final e = Uri.tryParse('${j['endpoint']}');
    if (e == null || e.host.isEmpty) return null;
    return BackupConfig(endpoint: e, deviceToken: j['device_token'] as String?, auto: j['auto'] != false);
  }

  /// "192.168.1.27:8080", "backup.example.org" or a full URL; http:// is
  /// assumed and the API's default port 8080 when none is given.
  static Uri? parseEndpoint(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    final hadScheme = s.contains('://');
    if (!hadScheme) s = 'http://$s';
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty) return null;
    return !hadScheme && !u.hasPort ? u.replace(port: 8080) : u;
  }
}

class BackupError implements Exception {
  const BackupError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The backup endpoint's HTTP API (NeoMtProto Http/BackupApi.cs). Every TLS
/// certificate is accepted, as for the custom server key.
class BackupApiClient {
  BackupApiClient(this.endpoint);

  final Uri endpoint;

  Uri _u(String path) => endpoint.replace(path: '${endpoint.path.replaceAll(RegExp(r'/+$'), '')}$path');

  Future<(int, List<int>)> _send(
    String method,
    String path, {
    Object? json,
    List<int>? body,
    Map<String, String>? headers,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..badCertificateCallback = (_, _, _) => true;
    try {
      final req = await client.openUrl(method, _u(path));
      headers?.forEach(req.headers.set);
      if (json != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(json)));
      } else if (body != null) {
        req.headers.contentType = ContentType.binary;
        req.contentLength = body.length;
        req.add(body);
      }
      final res = await req.close().timeout(const Duration(seconds: 60));
      final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      return (res.statusCode, bytes);
    } on SocketException catch (e) {
      throw BackupError('Cannot reach ${endpoint.host}: ${e.osError?.message ?? e.message}');
    } on TimeoutException {
      throw BackupError('${endpoint.host} timed out');
    } finally {
      client.close(force: true);
    }
  }

  static String _error(int status, List<int> body) {
    try {
      final j = jsonDecode(utf8.decode(body));
      if (j is Map && j['error'] is String) return j['error'] as String;
    } catch (_) {}
    return 'HTTP $status';
  }

  /// Uploads [data]; returns the device token that owns [name] (new on the
  /// first upload).
  Future<String> put(String name, List<int> data, {String? deviceToken, String? label}) async {
    final (s, b) = await _send(
      'PUT',
      '/api/open-backups/$name',
      body: data,
      headers: {
        'X-Device-Token': ?deviceToken,
        if (label != null) 'X-Backup-Label': Uri.encodeComponent(label),
      },
    );
    if (s == 404) throw const BackupError('This server has no open backups (enable Server:OpenBackups)');
    if (s != 200) throw BackupError(_error(s, b));
    return (jsonDecode(utf8.decode(b)) as Map)['device_token'] as String;
  }

  Future<List<BackupInfo>> list() async {
    final (s, b) = await _send('GET', '/api/open-backups');
    if (s == 404) throw const BackupError('This server has no open backups (enable Server:OpenBackups)');
    if (s != 200) throw BackupError(_error(s, b));
    return [
      for (final j in jsonDecode(utf8.decode(b)) as List)
        BackupInfo(
          name: (j as Map)['name'] as String,
          label: j['label'] == null ? null : Uri.decodeComponent(j['label'] as String),
          size: (j['size'] as num).toInt(),
          created: DateTime.fromMillisecondsSinceEpoch((j['created'] as num).toInt() * 1000),
        ),
    ]..sort((a, b) => b.created.compareTo(a.created));
  }

  Future<List<int>> get(String name) async {
    final (s, b) = await _send('GET', '/api/open-backups/$name');
    if (s != 200) throw BackupError(_error(s, b));
    return b;
  }

  /// Removes a backup from the server (anyone can: the phone restoring it
  /// has no device token). A backup that's already gone counts as deleted.
  Future<void> delete(String name) async {
    final (s, b) = await _send('DELETE', '/api/open-backups/$name');
    if (s == 405) throw const BackupError('This backup server is too old to delete backups');
    if (s != 200 && s != 404) throw BackupError(_error(s, b));
  }
}

class BackupInfo {
  const BackupInfo({required this.name, required this.size, required this.created, this.label});

  final String name;

  /// Who it belongs to, as the uploading Lumina described it.
  final String? label;
  final int size;
  final DateTime created;

  /// "Telegram" or "Custom server", from the name Lumina gave it.
  String get kind => name.startsWith('lumina-tg-')
      ? 'Telegram'
      : name.startsWith('lumina-s')
      ? 'Custom server'
      : 'Backup';
}

/// Restoring is staged: the decrypted bundle is written next to TDLib's data
/// and applied by [applyPending] at the next start, before any TDLib client
/// opens a database (overwriting an open one would corrupt it).
class SessionRestore {
  static File _pending(String supportDir) => File('$supportDir/restore_pending.bin');
  static const _stageKey = 'session_restore.stage_key';

  /// Checks the bundle and stages it, encrypted with a fresh Keystore key.
  static Future<void> stage(String supportDir, SecureStore secure, List<int> data) async {
    final payload = await SessionBundle.open(data);
    if (payload['v'] != 1 || payload['files'] is! Map || payload['database_key'] is! String) {
      throw const BackupError('This backup was made by a newer Lumina');
    }
    final key = SecretKeyData.random(length: 32).bytes;
    await secure.writeSecret(_stageKey, base64Encode(key));
    final sealed = await SessionBundle.seal(key, utf8.encode(jsonEncode(payload)));
    await _pending(supportDir).writeAsBytes(sealed, flush: true);
  }

  /// At startup: server settings, the database key and the session files go
  /// in place; the target account's old data (if any) is cleared first.
  /// Puts a staged backup in place as the [account]'s data (the active one:
  /// restore runs from the sign-in screen).
  static Future<void> applyPending(String supportDir, SecureStore secure, {AccountStore? accounts}) async {
    final f = _pending(supportDir);
    if (!await f.exists()) return;
    try {
      final key = await secure.readSecret(_stageKey);
      if (key == null) return;
      final clear = await SessionBundle.unseal(base64Decode(key), await f.readAsBytes());
      final p = jsonDecode(utf8.decode(clear)) as Map;
      final server = CustomServer.fromJson(p['server']);
      await CustomServer.save(supportDir, server);
      final TdPaths paths;
      if (accounts != null && !accounts.active.legacy) {
        accounts.active.server = server?.toJson();
        await accounts.save();
        paths = await TdPaths.forAccount(accounts.active);
      } else {
        paths = await TdPaths.resolve(serverId: server?.storageId);
      }
      await paths.wipe();
      await Directory(paths.database).create(recursive: true);
      await Directory(paths.files).create(recursive: true);
      for (final e in (p['files'] as Map).entries) {
        final name = '${e.key}';
        if (name.contains('/') || name.contains('..')) continue;
        await File('${paths.database}/$name').writeAsBytes(base64Decode(e.value as String), flush: true);
      }
      await secure.setDatabaseEncryptionKey(p['database_key'] as String, scope: paths.serverId);
    } finally {
      // Never re-applied, even if it failed half way (no loop on a bad file).
      if (await f.exists()) await f.delete();
      await secure.writeSecret(_stageKey, null);
    }
  }
}

/// Backup bundles. `LUMBK0\n` + JSON is the plain (debug) format uploaded
/// today; `LUMBK1\n` + header + AES-256-GCM is the passphrase format kept for
/// later. [seal]/[unseal] encrypt files kept on the phone with a raw key.
class SessionBundle {
  static const plainMagic = 'LUMBK0\n';
  static const magic = 'LUMBK1\n';
  static const iterations = 200000;

  static Uint8List plain(Map<String, Object?> payload) =>
      Uint8List.fromList(utf8.encode('$plainMagic${jsonEncode(payload)}'));

  /// Reads a bundle: plain ones directly, passphrase ones with [passphrase].
  static Future<Map<String, Object?>> open(List<int> data, {String? passphrase}) async {
    final head = utf8.decode(data.take(8).toList(), allowMalformed: true);
    if (head.startsWith(plainMagic)) {
      return (jsonDecode(utf8.decode(data.sublist(plainMagic.length))) as Map).cast<String, Object?>();
    }
    if (!head.startsWith(magic)) throw const BackupError('Not a Lumina session backup');
    if (passphrase == null) throw const BackupError('This backup is passphrase-protected');
    return decrypt(passphrase, data);
  }

  static Future<Uint8List> seal(List<int> key, List<int> clear) async {
    final box = await AesGcm.with256bits().encrypt(clear, secretKey: SecretKey(key));
    return Uint8List.fromList(box.concatenation());
  }

  static Future<List<int>> unseal(List<int> key, List<int> sealed) => AesGcm.with256bits().decrypt(
    SecretBox.fromConcatenation(sealed, nonceLength: 12, macLength: 16),
    secretKey: SecretKey(key),
  );

  static Future<SecretKey> _key(String passphrase, List<int> salt, int iterations) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  ).deriveKeyFromPassword(password: passphrase, nonce: salt);

  static Future<Uint8List> encrypt(String passphrase, Map<String, Object?> payload) async {
    final aes = AesGcm.with256bits();
    final salt = SecretKeyData.random(length: 16).bytes;
    final key = await _key(passphrase, salt, iterations);
    final box = await aes.encrypt(utf8.encode(jsonEncode(payload)), secretKey: key);
    final header = jsonEncode({
      'kdf': 'pbkdf2-sha256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'cipher': 'aes-256-gcm',
      'nonce': base64Encode(box.nonce),
    });
    return Uint8List.fromList([...utf8.encode('$magic$header\n'), ...box.cipherText, ...box.mac.bytes]);
  }

  static Future<Map<String, Object?>> decrypt(String passphrase, List<int> data) async {
    final text = utf8.decode(data.take(4096).toList(), allowMalformed: true);
    if (!text.startsWith(magic)) throw const BackupError('Not a Lumina session backup');
    final nl = text.indexOf('\n', magic.length);
    final header = jsonDecode(text.substring(magic.length, nl)) as Map;
    final body = data.sublist(nl + 1); // header is ASCII
    final key = await _key(passphrase, base64Decode(header['salt'] as String), header['iterations'] as int);
    try {
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(
          body.sublist(0, body.length - 16),
          nonce: base64Decode(header['nonce'] as String),
          mac: Mac(body.sublist(body.length - 16)),
        ),
        secretKey: key,
      );
      return (jsonDecode(utf8.decode(clear)) as Map).cast<String, Object?>();
    } on SecretBoxAuthenticationError {
      throw const BackupError('Wrong passphrase (or the backup is damaged)');
    }
  }
}

enum BackupState { idle, running, ok, failed }

/// Backs up the signed-in session (Telegram or a custom server): TDLib's
/// binlog (auth key and settings, encrypted with the database key), that
/// database key, and the server it belongs to, so a fresh install can
/// restore it. Automatically on sign-in and then about once a day.
class SessionBackupService extends ChangeNotifier {
  SessionBackupService({required this.paths, required this.secure});

  final TdPaths paths;
  final SecureStore secure;

  static const _configKey = 'session_backup.config';
  static const _lastKey = 'session_backup.last';
  static const interval = Duration(hours: 24);

  BackupConfig? config;
  DateTime? lastBackup;
  BackupState state = BackupState.idle;
  String? lastError;
  int? _userId;
  String? _label;
  Timer? _timer;
  var _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await secure.readSecret(_configKey);
    config = raw == null ? null : BackupConfig.fromJson(jsonDecode(raw));
    final last = await secure.readSecret(_lastKey);
    lastBackup = last == null ? null : DateTime.fromMillisecondsSinceEpoch(int.parse(last));
    notifyListeners();
  }

  Future<void> configure(BackupConfig c) async {
    config = c;
    _loaded = true;
    await secure.writeSecret(_configKey, jsonEncode(c.toJson()));
    notifyListeners();
    _schedule();
  }

  Future<void> setAuto(bool auto) async {
    final c = config;
    if (c == null) return;
    config = c.copyWith(auto: auto);
    await secure.writeSecret(_configKey, jsonEncode(config!.toJson()));
    notifyListeners();
    _schedule();
  }

  Future<void> disconnect() async {
    config = null;
    await secure.writeSecret(_configKey, null);
    _timer?.cancel();
    notifyListeners();
  }

  /// The account is ready: back it up now (a sign-in may be a different
  /// account), then about daily. [label] names it in the server's list.
  Future<void> onSignedIn(int userId, {String? label}) async {
    _userId = userId;
    _label = label;
    await load();
    _schedule();
    if (config?.auto == true) await backupNow().catchError((_) {});
  }

  void _schedule() {
    _timer?.cancel();
    if (config?.auto != true || _userId == null) return;
    _timer = Timer.periodic(const Duration(hours: 1), (_) => _maybeRun());
  }

  Future<void> _maybeRun() async {
    final c = config;
    if (c == null || !c.auto || state == BackupState.running) return;
    final last = lastBackup;
    if (last != null && DateTime.now().difference(last) < interval) return;
    await backupNow().catchError((_) {});
  }

  /// One rolling backup per account and server.
  static String backupName(String? serverId, int userId) =>
      'lumina-${serverId == null ? 'tg' : 's${serverId.substring(0, 8)}'}-$userId';

  Future<void> backupNow() async {
    final c = config, userId = _userId;
    if (c == null) throw const BackupError('Set up session backup first');
    if (userId == null) throw const BackupError('Sign in first');
    state = BackupState.running;
    lastError = null;
    notifyListeners();
    try {
      final binlog = File('${paths.database}/td.binlog');
      if (!await binlog.exists()) throw const BackupError('No session to back up yet');
      final support = await getApplicationSupportDirectory();
      final payload = <String, Object?>{
        'v': 1,
        'created': DateTime.now().toUtc().toIso8601String(),
        'user_id': userId,
        'server': CustomServer.load(support.path)?.toJson(),
        'database_key': await secure.databaseEncryptionKey(scope: paths.serverId),
        'files': {'td.binlog': base64Encode(await binlog.readAsBytes())},
      };
      // Debugging: uploaded unencrypted (SessionBundle.encrypt for later).
      final token = await BackupApiClient(c.endpoint).put(
        backupName(
          paths.server ?? (paths.serverId?.startsWith('acct-') == true ? null : paths.serverId),
          userId,
        ),
        SessionBundle.plain(payload),
        deviceToken: c.deviceToken,
        label: _label,
      );
      if (token != c.deviceToken) {
        config = c.copyWith(deviceToken: token);
        await secure.writeSecret(_configKey, jsonEncode(config!.toJson()));
      }
      lastBackup = DateTime.now();
      await secure.writeSecret(_lastKey, '${lastBackup!.millisecondsSinceEpoch}');
      state = BackupState.ok;
    } catch (e) {
      state = BackupState.failed;
      lastError = e is BackupError ? e.message : '$e';
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
