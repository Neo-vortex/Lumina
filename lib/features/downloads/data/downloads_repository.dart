import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/tdlib/td_client.dart';

/// TDLib's download list (what the Downloads screen shows).
class DownloadsRepository {
  DownloadsRepository(this._client);

  final TdClient _client;

  Stream<td.Update> get updates => _client.updates.where(
    (u) =>
        u is td.UpdateFileAddedToDownloads ||
        u is td.UpdateFileDownload ||
        u is td.UpdateFileRemovedFromDownloads ||
        u is td.UpdateFileDownloads ||
        u is td.UpdateFile,
  );

  Future<void> add(int fileId, {required int chatId, required int messageId, int priority = 16}) =>
      _client.invoke<td.File>(
        td.AddFileToDownloads(fileId: fileId, chatId: chatId, messageId: messageId, priority: priority),
      );

  Future<void> setPaused(int fileId, bool paused) =>
      _client.invoke<td.Ok>(td.ToggleDownloadIsPaused(fileId: fileId, isPaused: paused));

  Future<void> setAllPaused(bool paused) =>
      _client.invoke<td.Ok>(td.ToggleAllDownloadsArePaused(arePaused: paused));

  Future<void> remove(int fileId, {required bool deleteFile}) =>
      _client.invoke<td.Ok>(td.RemoveFileFromDownloads(fileId: fileId, deleteFromCache: deleteFile));

  Future<td.FoundFileDownloads> search({
    String query = '',
    bool onlyActive = false,
    bool onlyCompleted = false,
    String offset = '',
    int limit = 50,
  }) => _client.invoke<td.FoundFileDownloads>(
    td.SearchFileDownloads(
      query: query,
      onlyActive: onlyActive,
      onlyCompleted: onlyCompleted,
      offset: offset,
      limit: limit,
    ),
  );

  Future<void> setPriority(int fileId, int priority) => _client.invoke<td.File>(
    td.DownloadFile(fileId: fileId, priority: priority, offset: 0, limit: 0, synchronous: false),
  );
}
