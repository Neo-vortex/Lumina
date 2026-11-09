import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../accounts/account_store.dart';

/// Absolute TDLib directories under the app-private support directory.
class TdPaths {
  const TdPaths(this.database, this.files, {this.serverId, this.server});

  final String database;
  final String files;

  /// The custom server these belong to (CustomServer.storageId); null for
  /// Telegram.
  final String? serverId;

  /// The custom server's storage id (backup names); null for Telegram. For
  /// accounts [serverId] is the account's key scope instead.
  final String? server;

  /// The folders and key scope of one account (see AccountStore).
  static Future<TdPaths> forAccount(Account account) async {
    final root = await getApplicationSupportDirectory();
    final base = '${root.path}/${account.dirName()}';
    return TdPaths(
      '$base/db',
      '$base/files',
      serverId: account.keyScope,
      server: account.customServer?.storageId,
    );
  }

  /// A custom server (see CustomServer) gets its own folder, so its account
  /// never mixes with the Telegram one.
  static Future<TdPaths> resolve({String? serverId}) async {
    final root = await getApplicationSupportDirectory();
    final base = serverId == null ? '${root.path}/tdlib' : '${root.path}/tdlib-server-$serverId';
    return TdPaths('$base/db', '$base/files', serverId: serverId);
  }

  /// Deletes every TDLib file. Only safe once the client is closed.
  Future<void> wipe() async {
    for (final path in [database, files]) {
      final dir = Directory(path);
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }
}
