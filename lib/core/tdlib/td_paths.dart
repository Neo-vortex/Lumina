import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Absolute TDLib directories under the app-private support directory.
class TdPaths {
  const TdPaths(this.database, this.files);

  final String database;
  final String files;

  static Future<TdPaths> resolve() async {
    final root = await getApplicationSupportDirectory();
    return TdPaths('${root.path}/tdlib/db', '${root.path}/tdlib/files');
  }

  /// Deletes every TDLib file. Only safe once the client is closed.
  Future<void> wipe() async {
    for (final path in [database, files]) {
      final dir = Directory(path);
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }
}
