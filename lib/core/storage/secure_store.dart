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
  Future<String> databaseEncryptionKey() async {
    final existing = await _storage.read(key: _dbKey);
    if (existing != null) return existing;
    final random = Random.secure();
    final key = base64Encode(List<int>.generate(32, (_) => random.nextInt(256)));
    await _storage.write(key: _dbKey, value: key);
    return key;
  }

  /// Forgets the database key; call only after the database itself is gone.
  Future<void> discardDatabaseEncryptionKey() => _storage.delete(key: _dbKey);
}
