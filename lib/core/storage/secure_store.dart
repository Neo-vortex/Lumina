import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keystore-backed storage for secrets. Non-secret preferences belong in
/// shared_preferences instead.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _dbKey = 'tdlib.database_encryption_key';

  /// The TDLib database encryption key (base64, as TDLib's JSON `bytes`),
  /// generated on first use.
  ///
  /// If the Keystore entry is lost while the database survives, TDLib rejects
  /// the key and the app offers "Reset local data". Auto-backup is disabled in
  /// the manifest so a restored database never arrives without its key.
  ///
  /// [scope] names the database (a custom server's storage id; null for
  /// Telegram), so restoring one account's key never breaks another's.
  Future<String> databaseEncryptionKey({String? scope}) async {
    final name = _keyName(scope);
    final existing = await _storage.read(key: name);
    if (existing != null) return existing;
    final random = Random.secure();
    final key = base64Encode(List<int>.generate(32, (_) => random.nextInt(256)));
    await _storage.write(key: name, value: key);
    return key;
  }

  /// Puts a restored database's key in place.
  Future<void> setDatabaseEncryptionKey(String key, {String? scope}) =>
      _storage.write(key: _keyName(scope), value: key);

  static String _keyName(String? scope) => scope == null ? _dbKey : '$_dbKey.$scope';

  Future<String?> readSecret(String key) => _storage.read(key: 'secret.$key');

  Future<void> writeSecret(String key, String? value) =>
      value == null ? _storage.delete(key: 'secret.$key') : _storage.write(key: 'secret.$key', value: value);

  /// Forgets the database key; call only after the database itself is gone.
  Future<void> discardDatabaseEncryptionKey({String? scope}) => _storage.delete(key: _keyName(scope));
}
