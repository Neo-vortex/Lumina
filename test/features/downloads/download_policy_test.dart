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

  test('on mobile data Wi-Fi-only downloads wait, and resume on Wi-Fi', () async {
    final p = policy();
    await p.setWifiOnly(1, true);
    net.set(false);
    await p.apply([1, 2]);
    expect(toggles(), [(1, true)]);
    expect(p.isWaitingForWifi(1), isTrue);
    net.set(true);
    await p.apply([1, 2]);
    expect(toggles(), [(1, true), (1, false)]);
    expect(p.isWaitingForWifi(1), isFalse);
  });

  test("a download the user paused is never resumed by the network", () async {
    final p = policy();
    await p.setWifiOnly(1, true);
    p.userPaused(1, true);
    net.set(false);
    await p.apply([1]);
    net.set(true);
    await p.apply([1]);
    net.set(false);
    await p.apply([1]);
    expect(toggles(), isEmpty);
  });

  test('the default applies to new downloads and flags survive a restart', () async {
    prefs.downloadsWifiOnlyDefault = true;
    final p = policy()..onAdded(7);
    expect(p.isWifiOnly(7), isTrue);
    expect(policy().isWifiOnly(7), isTrue, reason: 'stored in prefs');
  });
}
