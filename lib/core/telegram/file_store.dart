import 'dart:async';

import 'package:lumina_tdlib/api.dart' as td;

import '../tdlib/td_client.dart';

/// Latest known state of every TDLib file, kept current by `updateFile`.
/// Transfers are TDLib's own (spec §7.3); this only starts, cancels and
/// observes them.
class FileStore {
  FileStore(this._client) {
    _subscription = _client.updates.listen((u) {
      if (u is td.UpdateFile) remember(u.file);
      if (u case td.UpdateAuthorizationState(authorizationState: td.AuthorizationStateClosed())) clear();
    });
  }

  final TdClient _client;
  StreamSubscription<td.Update>? _subscription;
  final _files = <int, td.File>{};
  final _changes = StreamController<td.File>.broadcast(sync: true);

  td.File? operator [](int fileId) => _files[fileId];

  /// Records a file seen inside a message, photo or update.
  void remember(td.File file) {
    _files[file.id] = file;
    if (!_changes.isClosed) _changes.add(file);
  }

  /// Current state (if known) followed by every change of [fileId].
  Stream<td.File> watch(int fileId) async* {
    final current = _files[fileId];
    if (current != null) yield current;
    yield* _changes.stream.where((f) => f.id == fileId);
  }

  /// Starts (or reprioritises) a full download; progress arrives via [watch].
  Future<void> download(int fileId, {int priority = 16}) async {
    final file = await _client.invoke<td.File>(
      td.DownloadFile(fileId: fileId, priority: priority, offset: 0, limit: 0, synchronous: false),
    );
    remember(file);
  }

  /// Downloads a whole file and completes with its local path.
  Future<String> downloadAndWait(int fileId, {int priority = 24}) async {
    final file = await _client.invoke<td.File>(
      td.DownloadFile(fileId: fileId, priority: priority, offset: 0, limit: 0, synchronous: true),
    );
    remember(file);
    if (!file.local.isDownloadingCompleted) {
      throw StateError('Download of file $fileId did not complete');
    }
    return file.local.path;
  }

  /// Asks TDLib for a byte range (streaming). Returns immediately.
  Future<void> requestRange(int fileId, int offset, {int limit = 0, int priority = 32}) async {
    final file = await _client.invoke<td.File>(
      td.DownloadFile(fileId: fileId, priority: priority, offset: offset, limit: limit, synchronous: false),
    );
    remember(file);
  }

  /// Bytes available contiguously from [offset].
  Future<int> downloadedPrefix(int fileId, int offset) async {
    final result = await _client.invoke<td.FileDownloadedPrefixSize>(
      td.GetFileDownloadedPrefixSize(fileId: fileId, offset: offset),
    );
    return result.size;
  }

  Future<td.File> refresh(int fileId) async {
    final file = await _client.invoke<td.File>(td.GetFile(fileId: fileId));
    remember(file);
    return file;
  }

  Future<void> cancel(int fileId) =>
      _client.invoke<td.Ok>(td.CancelDownloadFile(fileId: fileId, onlyIfPending: false));

  void clear() => _files.clear();

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _changes.close();
  }
}
