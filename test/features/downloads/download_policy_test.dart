import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/downloads/data/download_policy.dart';
import 'package:lumina/features/downloads/data/downloads_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

class NetForTests extends ChangeNotifier implements NetworkWatch {
  @override
  bool onWifi = true;

  @override
  Listenable get changes => this;

  void set(bool wifi) {
    onWifi = wifi;
    notifyListeners();
  }
}

void main() {
  late FakeTdClient client;
  late NetForTests net;
  late AppPreferences prefs;

  DownloadPolicy policy() =>
      DownloadPolicy(repository: DownloadsRepository(client), prefs: prefs, network: net);
  List<(int, bool)> toggles() => [
    for (final t in client.sentOf<td.ToggleDownloadIsPaused>()) (t.fileId, t.isPaused),
  ];

  setUp(() {
    client = FakeTdClient();
    net = NetForTests();
    prefs = AppPreferences.inMemory();
  });

  // What TDLib says about the active downloads.
  List<({int id, bool paused})> active(Map<int, bool> paused) => [
    for (final e in paused.entries) (id: e.key, paused: e.value),
  ];

  test('on mobile data Wi-Fi-only downloads wait, and resume on Wi-Fi', () async {
    final p = policy();
    await p.setWifiOnly(1, true);
    net.set(false);
    await p.apply(active({1: false, 2: false}));
    expect(toggles(), [(1, true)]);
    expect(p.isWaitingForWifi(1), isTrue);
    net.set(true);
    await p.apply(active({1: true, 2: false}));
    expect(toggles(), [(1, true), (1, false)]);
    expect(p.isWaitingForWifi(1), isFalse);
  });

  test('a download already paused (by the user, or Pause all) is never resumed by the network', () async {
    final p = policy();
    await p.setWifiOnly(1, true);
    net.set(false);
    await p.apply(active({1: true}));
    net.set(true);
    await p.apply(active({1: true}));
    net.set(false);
    await p.apply(active({1: true}));
    expect(toggles(), isEmpty);
  });

  test('a download Lumina paused still resumes on Wi-Fi after a restart', () async {
    await policy().setWifiOnly(1, true);
    net.set(false);
    await policy().apply(active({1: false}));
    final restarted = policy();
    expect(restarted.isWaitingForWifi(1), isTrue, reason: 'remembered in prefs');
    net.set(true);
    await restarted.apply(active({1: true}));
    expect(toggles(), [(1, true), (1, false)]);
  });

  test('resuming a waiting download by hand lets it use mobile data', () async {
    final p = policy();
    await p.setWifiOnly(1, true);
    net.set(false);
    await p.apply(active({1: false}));
    await p.userResumed(1);
    await p.apply(active({1: false}));
    expect(toggles(), [(1, true)], reason: 'not paused again');
    expect(p.isWifiOnly(1), isFalse);
  });

  test('the default applies to new downloads and flags survive a restart', () async {
    prefs.downloadsWifiOnlyDefault = true;
    final p = policy()..onAdded(7);
    expect(p.isWifiOnly(7), isTrue);
    expect(policy().isWifiOnly(7), isTrue, reason: 'stored in prefs');
  });
}
