import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/features/downloads/bloc/downloads_cubit.dart';
import 'package:lumina/features/downloads/data/download_notifier.dart';
import 'package:lumina/features/downloads/data/downloads_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'downloads_cubit_test.dart' show counts, dl;

class FakeChannel implements DownloadsChannel {
  final calls = <String>[];
  final _events = StreamController<String>.broadcast();

  @override
  Future<void> progress(int count, int percent) async => calls.add('progress $count');

  @override
  Future<void> clearProgress() async => calls.add('clear');

  @override
  Future<void> completed(int id, String name, String path) async => calls.add('done $id');

  @override
  Stream<String> get events => _events.stream;

  void emit(String e) => _events.add(e);
}

void main() {
  test(
    'progress while active, a note per completion, clear when done, pause all from the notification',
    () async {
      final client = FakeTdClient()
        ..respond = (f) => f is td.SearchFileDownloads
            ? td.FoundFileDownloads(
                totalCounts: counts,
                files: f.onlyActive ? [dl(1)] : const [],
                nextOffset: '',
              )
            : const td.Ok();
      final cubit = DownloadsCubit(repository: DownloadsRepository(client), files: FileStore(client));
      final channel = FakeChannel();
      final notifier = DownloadNotifier(cubit: cubit, channel: channel);
      await cubit.start();
      await pumpEventQueue();
      expect(channel.calls, contains('progress 1'));
      client.emitUpdate(
        const td.UpdateFileDownload(fileId: 1, completeDate: 9, isPaused: false, counts: counts),
      );
      await pumpEventQueue();
      expect(channel.calls, containsAllInOrder(['done 1', 'clear']));
      channel.emit('pauseAll');
      await pumpEventQueue();
      expect(client.sentOf<td.ToggleAllDownloadsArePaused>().single.arePaused, isTrue);
      notifier.dispose();
      await cubit.close();
    },
  );
}
