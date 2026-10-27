import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/download_registry.dart';
import 'downloads_repository.dart';

/// Puts every download over 1 MB into TDLib's download list, once.
class TdlibDownloadRegistry implements DownloadRegistry {
  TdlibDownloadRegistry(this._repo, {int Function()? defaultPriority})
    : _priority = defaultPriority ?? (() => 16);

  static const threshold = 1024 * 1024;

  final DownloadsRepository _repo;
  final int Function() _priority;
  final _tracked = <int>{};

  @override
  void track(td.File file, td.Message message) {
    final size = file.size > 0 ? file.size : file.expectedSize;
    if (size <= threshold) return;
    if (file.local.isDownloadingCompleted || !file.local.canBeDownloaded) return;
    if (!_tracked.add(file.id)) return;
    _add(file.id, message);
  }

  Future<void> _add(int fileId, td.Message message) async {
    try {
      await _repo.add(fileId, chatId: message.chatId, messageId: message.id, priority: _priority());
    } catch (_) {
      _tracked.remove(fileId); // try again next time
    }
  }
}
