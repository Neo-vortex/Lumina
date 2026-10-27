import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/app/downloads_hub.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/features/downloads/bloc/downloads_cubit.dart';
import 'package:lumina/features/downloads/data/download_policy.dart';
import 'package:lumina/features/downloads/data/downloads_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../features/downloads/download_notifier_test.dart' show FakeChannel;
import '../features/downloads/download_policy_test.dart' show NetForTests;
import '../features/downloads/downloads_cubit_test.dart' show counts, dl;
import '../helpers/fakes.dart';

void main() {
  late FakeTdClient client;
  late NetForTests net;
  late AppPreferences prefs;

  DownloadsHub hub({bool readyAlready = false}) {
    client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetAuthorizationState() =>
          readyAlready ? const td.AuthorizationStateReady() : const td.AuthorizationStateWaitPhoneNumber(),
        td.SearchFileDownloads(onlyActive: true) => td.FoundFileDownloads(
          totalCounts: counts,
          files: [dl(1)],
          nextOffset: '',
        ),
        td.SearchFileDownloads() => const td.FoundFileDownloads(
          totalCounts: counts,
          files: [],
          nextOffset: '',
        ),
        _ => const td.Ok(),
      };
    final repo = DownloadsRepository(client);
    return DownloadsHub(
      client: client,
      cubit: DownloadsCubit(repository: repo, files: FileStore(client)),
      policy: DownloadPolicy(repository: repo, prefs: prefs, network: net),
      channel: FakeChannel(),
    );
  }

  setUp(() {
    net = NetForTests();
    prefs = AppPreferences.inMemory();
  });

  test('loads the list even when TDLib was logged in before the hub existed', () async {
    final h = hub(readyAlready: true);
    await pumpEventQueue();
    expect(h.cubit.state.active.map((i) => i.fileId), [1]);
    h.dispose();
  });

  test('a new Wi-Fi-only download on mobile data is paused right away', () async {
    prefs.downloadsWifiOnlyDefault = true;
    net.onWifi = false;
    final h = hub(readyAlready: true);
    await pumpEventQueue();
    client.emitUpdate(td.UpdateFileAddedToDownloads(fileDownload: dl(2), counts: counts));
    await pumpEventQueue();
    final paused = client.sentOf<td.ToggleDownloadIsPaused>().where((t) => t.isPaused).map((t) => t.fileId);
    expect(paused, contains(2));
    h.dispose();
  });
}
