import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/features/downloads/bloc/downloads_cubit.dart';
import 'package:lumina/features/downloads/data/downloads_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'downloads_repository_test.dart' show file;

const counts = td.DownloadedFileCounts(activeCount: 0, pausedCount: 0, completedCount: 0);

td.FileDownload dl(int id, {int complete = 0, bool paused = false, td.MessageContent? content}) =>
    td.FileDownload(
      fileId: id,
      message: fakeMessage(id, content: content),
      addDate: 100 + id,
      completeDate: complete,
      isPaused: paused,
    );

void main() {
  late FakeTdClient client;
  late DownloadsCubit cubit;
  var clock = DateTime(2026);

  Future<void> start({
    List<td.FileDownload> active = const [],
    List<td.FileDownload> done = const [],
    String more = '',
  }) async {
    client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.SearchFileDownloads(onlyActive: true) => td.FoundFileDownloads(
          totalCounts: counts,
          files: active,
          nextOffset: '',
        ),
        td.SearchFileDownloads(onlyCompleted: true, offset: '') => td.FoundFileDownloads(
          totalCounts: counts,
          files: done,
          nextOffset: more,
        ),
        td.SearchFileDownloads() => td.FoundFileDownloads(
          totalCounts: counts,
          files: [dl(99, complete: 5)],
          nextOffset: '',
        ),
        td.DownloadFile(:final fileId) => file(fileId, 10),
        _ => const td.Ok(),
      };
    cubit = DownloadsCubit(
      repository: DownloadsRepository(client),
      files: FileStore(client),
      now: () => clock,
    );
    await cubit.start();
  }

  tearDown(() => cubit.close());

  test('loads active and completed from TDLib (survives restarts)', () async {
    await start(active: [dl(1), dl(2, paused: true)], done: [dl(3, complete: 200)]);
    expect(cubit.state.active.map((i) => i.fileId), [1, 2]);
    expect(cubit.state.completed.map((i) => i.fileId), [3]);
    expect(cubit.state.active[1].isPaused, isTrue);
  });

  test('updates add, complete and remove; totals follow', () async {
    await start(active: [dl(1)]);
    client.emitUpdate(td.UpdateFileAddedToDownloads(fileDownload: dl(2), counts: counts));
    client.emitUpdate(
      const td.UpdateFileDownload(fileId: 1, completeDate: 300, isPaused: false, counts: counts),
    );
    client.emitUpdate(const td.UpdateFileDownloads(totalSize: 1000, totalCount: 1, downloadedSize: 250));
    await pumpEventQueue();
    expect(cubit.state.active.map((i) => i.fileId), [2]);
    expect(cubit.state.completed.map((i) => i.fileId), [1]);
    expect((cubit.state.totalSize, cubit.state.downloadedSize), (1000, 250));
    client.emitUpdate(const td.UpdateFileRemovedFromDownloads(fileId: 2, counts: counts));
    await pumpEventQueue();
    expect(cubit.state.active, isEmpty);
    expect(cubit.state.anyActive, isFalse);
  });

  test('completed downloads page instead of loading all', () async {
    await start(done: [dl(3, complete: 1)], more: 'next');
    expect(cubit.state.hasMoreCompleted, isTrue);
    await cubit.loadMoreCompleted();
    expect(cubit.state.completed.map((i) => i.fileId), [3, 99]);
    expect(cubit.state.hasMoreCompleted, isFalse);
  });

  test('speed comes from progress over time', () async {
    await start(active: [dl(1)]);
    final f = file(1, 10000000);
    client.emitUpdate(
      td.UpdateFile(file: f.copyWith(local: f.local.copyWith(downloadedSize: 0, isDownloadingActive: true))),
    );
    await pumpEventQueue();
    clock = clock.add(const Duration(seconds: 1));
    client.emitUpdate(
      td.UpdateFile(
        file: f.copyWith(local: f.local.copyWith(downloadedSize: 1000000, isDownloadingActive: true)),
      ),
    );
    await pumpEventQueue();
    expect(cubit.state.bytesPerSecond, greaterThan(0));
  });

  test('filters and search narrow what is shown', () async {
    await start(
      active: [
        dl(
          1,
          content: const td.MessageText(
            text: td.FormattedText(text: 'x', entities: []),
          ),
        ),
        dl(
          2,
          content: td.MessagePhoto(
            photo: const td.Photo(hasStickers: false, sizes: []),
            caption: const td.FormattedText(text: '', entities: []),
            showCaptionAboveMedia: false,
            hasSpoiler: false,
            isSecret: false,
          ),
        ),
      ],
    );
    cubit.setFilter(DownloadFilter.photos);
    expect(cubit.state.visibleActive.map((i) => i.fileId), [2]);
    cubit
      ..setFilter(DownloadFilter.all)
      ..setQuery('PHOTO');
    expect(cubit.state.visibleActive.map((i) => i.fileId), [2]);
  });

  test('reordering sets priorities from the top', () async {
    await start(active: [dl(1), dl(2), dl(3)]);
    await cubit.reorder(2, 0);
    expect(cubit.state.active.map((i) => i.fileId), [3, 1, 2]);
    final p = {for (final d in client.sentOf<td.DownloadFile>()) d.fileId: d.priority};
    expect(p, {3: 32, 1: 31, 2: 30});
  });

  test('reordering never touches paused downloads (setting a priority would resume them)', () async {
    await start(active: [dl(1), dl(2, paused: true), dl(3)]);
    await cubit.reorder(2, 0);
    final touched = client.sentOf<td.DownloadFile>().map((d) => d.fileId).toSet();
    expect(touched, {3, 1});
  });

  test('loading more finished downloads runs once at a time and survives errors', () async {
    await start(done: [dl(3, complete: 1)], more: 'next');
    await Future.wait([cubit.loadMoreCompleted(), cubit.loadMoreCompleted(), cubit.loadMoreCompleted()]);
    expect(client.sentOf<td.SearchFileDownloads>().where((s) => s.offset == 'next'), hasLength(1));
    client.respond = (_) => const td.TdError(code: 500, message: 'down');
    cubit.emit(cubit.state.copyWith(hasMoreCompleted: true));
    await cubit.loadMoreCompleted(); // no throw
  });
}
