import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/downloads/data/downloads_repository.dart';
import 'package:lumina/features/downloads/data/tdlib_download_registry.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../core/telegram/transfer_ring_test.dart' show downloading;
import '../../helpers/fakes.dart';

td.File file(int id, int size, {bool done = false}) {
  final f = downloading(size: size);
  return f.copyWith(
    id: id,
    local: f.local.copyWith(isDownloadingActive: false, isDownloadingCompleted: done, downloadedSize: 0),
  );
}

void main() {
  test('requests are built from the arguments', () async {
    final client = FakeTdClient()
      ..respond = (f) => f is td.SearchFileDownloads
          ? const td.FoundFileDownloads(
              totalCounts: td.DownloadedFileCounts(activeCount: 0, pausedCount: 0, completedCount: 0),
              files: [],
              nextOffset: '',
            )
          : f is td.DownloadFile || f is td.AddFileToDownloads
          ? file(3, 10)
          : const td.Ok();
    final repo = DownloadsRepository(client);
    await repo.add(3, chatId: 1, messageId: 9, priority: 20);
    await repo.setPaused(3, true);
    await repo.setAllPaused(false);
    await repo.remove(3, deleteFile: true);
    await repo.search(query: 'mp4', onlyActive: true, offset: 'x', limit: 20);
    await repo.setPriority(3, 31);
    final add = client.sentOf<td.AddFileToDownloads>().single;
    expect((add.fileId, add.chatId, add.messageId, add.priority), (3, 1, 9, 20));
    expect(client.sentOf<td.ToggleDownloadIsPaused>().single.isPaused, isTrue);
    expect(client.sentOf<td.ToggleAllDownloadsArePaused>().single.arePaused, isFalse);
    expect(client.sentOf<td.RemoveFileFromDownloads>().single.deleteFromCache, isTrue);
    final s = client.sentOf<td.SearchFileDownloads>().single;
    expect((s.query, s.onlyActive, s.onlyCompleted, s.offset, s.limit), ('mp4', true, false, 'x', 20));
    expect(client.sentOf<td.DownloadFile>().single.priority, 31);
  });

  test('the registry tracks big files once, with their message, and skips the rest', () async {
    final client = FakeTdClient()..respond = (_) => file(3, 10);
    final registry = TdlibDownloadRegistry(DownloadsRepository(client));
    final m = fakeMessage(9, chatId: 1);
    registry.track(file(3, 5 * 1024 * 1024), m);
    registry.track(file(3, 5 * 1024 * 1024), m); // again
    registry.track(file(4, 1024 * 1024), m); // exactly 1 MB: not over
    registry.track(file(5, 9 * 1024 * 1024, done: true), m); // already downloaded
    await pumpEventQueue();
    final adds = client.sentOf<td.AddFileToDownloads>();
    expect(adds.map((a) => a.fileId), [3]);
    expect((adds.single.chatId, adds.single.messageId), (1, 9));
  });
}
