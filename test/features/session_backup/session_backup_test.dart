import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/session_backup/data/session_backup.dart';

/// A stand-in for NeoMtProto's /api/open-backups (Http/BackupApi.cs).
Future<HttpServer> fakeOpenBackups() async {
  final store = <String, ({List<int> data, String token, String? label})>{};
  var n = 0;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((r) async {
    final body = await r.fold<List<int>>([], (a, b) => a..addAll(b));
    void json(int status, Object o) => r.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(o))
      ..close();
    final path = r.uri.path;
    if (path == '/api/open-backups') {
      return json(200, [
        for (final e in store.entries)
          {'name': e.key, 'label': e.value.label, 'size': e.value.data.length, 'created': 1700000000},
      ]);
    }
    final name = path.substring('/api/open-backups/'.length);
    if (r.method == 'PUT') {
      final token = r.headers.value('x-device-token');
      final existing = store[name];
      if (existing != null && existing.token != token)
        return json(403, {'error': 'BACKUP_OWNED_BY_ANOTHER_DEVICE'});
      final owner = token ?? 'dev${++n}';
      store[name] = (data: body, token: owner, label: r.headers.value('x-backup-label') ?? existing?.label);
      return json(200, {'device_token': owner});
    }
    final d = store[name];
    if (d == null) return json(404, {'error': 'BACKUP_NOT_FOUND'});
    r.response
      ..add(d.data)
      ..close();
  });
  return server;
}

void main() {
  test('plain bundle round-trips', () async {
    final data = SessionBundle.plain({'v': 1, 'x': 'y'});
    expect(utf8.decode(data).startsWith('LUMBK0\n'), isTrue);
    expect((await SessionBundle.open(data))['x'], 'y');
  });

  test('passphrase bundle round-trips and rejects a wrong passphrase', () async {
    final data = await SessionBundle.encrypt('correct horse', {'v': 1, 'k': 'secret'});
    expect((await SessionBundle.open(data, passphrase: 'correct horse'))['k'], 'secret');
    expect(SessionBundle.open(data, passphrase: 'wrong'), throwsA(isA<BackupError>()));
    expect(SessionBundle.open(data), throwsA(isA<BackupError>()));
  });

  test('local seal/unseal', () async {
    final key = List<int>.generate(32, (i) => i);
    final sealed = await SessionBundle.seal(key, utf8.encode('session'));
    expect(utf8.decode(sealed, allowMalformed: true).contains('session'), isFalse);
    expect(utf8.decode(await SessionBundle.unseal(key, sealed)), 'session');
  });

  test('endpoint parsing assumes http and port 8080', () {
    expect('${BackupConfig.parseEndpoint('192.168.1.27')}', 'http://192.168.1.27:8080');
    expect('${BackupConfig.parseEndpoint('192.168.1.27:9000')}', 'http://192.168.1.27:9000');
    expect('${BackupConfig.parseEndpoint('https://b.example.org')}', 'https://b.example.org');
    expect(BackupConfig.parseEndpoint(''), isNull);
  });

  test('open backups: first upload owns the name; list shows the label; download', () async {
    final server = await fakeOpenBackups();
    try {
      final api = BackupApiClient(Uri.parse('http://127.0.0.1:${server.port}'));
      final name = SessionBackupService.backupName(null, 42);
      expect(name, 'lumina-tg-42');
      final bundle = SessionBundle.plain({'v': 1});
      final token = await api.put(name, bundle, label: 'Neo · ناصر (+98 912)');
      expect(await api.put(name, bundle, deviceToken: token), token);
      await expectLater(api.put(name, bundle), throwsA(isA<BackupError>()));
      final list = await api.list();
      expect(list.single.label, 'Neo · ناصر (+98 912)');
      expect(list.single.kind, 'Telegram');
      expect(await api.get(name), bundle);
    } finally {
      await server.close(force: true);
    }
  });
}
