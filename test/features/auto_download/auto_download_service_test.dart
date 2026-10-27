import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/auto_download/data/auto_download_service.dart';
import 'package:lumina/features/auto_download/data/network_monitor.dart';
import 'package:lumina/features/auto_download/domain/auto_download_policy.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'fake_monitor.dart';

const _base = td.AutoDownloadSettings(
  isAutoDownloadEnabled: true,
  maxPhotoFileSize: 1,
  maxVideoFileSize: 1,
  maxOtherFileSize: 1,
  videoUploadBitrate: 777,
  preloadLargeVideos: false,
  preloadNextAudio: true,
  preloadStories: true,
  useLessDataForCalls: false,
);

void main() {
  late FakeTdClient client;
  late FakeMonitor monitor;
  late AppPreferences prefs;
  late TelegramCache cache;

  AutoDownloadService service() =>
      AutoDownloadService(client: client, prefs: prefs, cache: cache, network: monitor);

  setUp(() {
    client = FakeTdClient()
      ..respond = (f) => f is td.GetAutoDownloadSettingsPresets
          ? const td.AutoDownloadSettingsPresets(low: _base, medium: _base, high: _base)
          : const td.Ok();
    monitor = FakeMonitor();
    prefs = AppPreferences.inMemory();
    cache = TelegramCache.detached();
  });

  test('defaults per network until changed, and changes persist', () async {
    final s = service();
    expect(s.policy(NetworkKind.wifi).preset, AutoDownloadPreset.high);
    await s.setPolicy(NetworkKind.wifi, AutoDownloadPolicy.of(AutoDownloadPreset.off));
    expect(service().policy(NetworkKind.wifi).preset, AutoDownloadPreset.off);
    s.dispose();
  });

  test('once logged in, every network is sent to TDLib along with the current network type', () async {
    final s = service();
    client.emit(const td.AuthorizationStateReady());
    await pumpEventQueue();
    final sets = client.sentOf<td.SetAutoDownloadSettings>();
    expect(sets.map((e) => e.type.runtimeType).toSet(), {
      td.NetworkTypeMobile,
      td.NetworkTypeWiFi,
      td.NetworkTypeMobileRoaming,
    });
    final wifi = sets.firstWhere((e) => e.type is td.NetworkTypeWiFi).settings;
    expect(wifi.videoUploadBitrate, 777, reason: 'server defaults kept');
    expect(wifi.maxVideoFileSize, AutoDownloadPolicy.of(AutoDownloadPreset.high).maxVideoSize);
    expect(wifi.preloadLargeVideos, isTrue);
    expect(client.sentOf<td.SetNetworkType>().single.type, isA<td.NetworkTypeWiFi>());
    s.dispose();
  });

  test('an off policy turns TDLib auto-download off for that network', () async {
    final s = service();
    client.emit(const td.AuthorizationStateReady());
    await pumpEventQueue();
    client.sent.clear();
    await s.setPolicy(NetworkKind.mobile, AutoDownloadPolicy.of(AutoDownloadPreset.off));
    final set = client.sentOf<td.SetAutoDownloadSettings>().single;
    expect(set.type, isA<td.NetworkTypeMobile>());
    expect(set.settings.isAutoDownloadEnabled, isFalse);
    expect(set.settings.maxVideoFileSize, 0);
    s.dispose();
  });

  test('network changes switch the policy in force and tell TDLib', () async {
    final s = service();
    client.emit(const td.AuthorizationStateReady());
    await pumpEventQueue();
    await s.setPolicy(NetworkKind.roaming, AutoDownloadPolicy.of(AutoDownloadPreset.off));
    final chat = fakeChat(9);
    cache.apply(td.UpdateNewChat(chat: chat));
    expect(s.allows(chatId: 9, media: MediaKind.photos, size: 10), isTrue);
    monitor.change(ConnectionType.roaming);
    await pumpEventQueue();
    expect(s.allows(chatId: 9, media: MediaKind.photos, size: 10), isFalse);
    expect(client.sentOf<td.SetNetworkType>().last.type, isA<td.NetworkTypeMobileRoaming>());
    s.dispose();
  });

  test('the chat kind comes from the cache: contacts, private, groups, channels', () {
    final s = service();
    // Wi-Fi, contacts only.
    s.setPolicy(
      NetworkKind.wifi,
      AutoDownloadPolicy.of(AutoDownloadPreset.off).toggled(MediaKind.photos, ChatKind.contacts),
    );
    cache
      ..apply(td.UpdateUser(user: fakeUser().copyWith(id: 9, isContact: true)))
      ..apply(td.UpdateNewChat(chat: fakeChat(9)))
      ..apply(td.UpdateNewChat(chat: fakeChat(10)));
    expect(s.chatKind(9), ChatKind.contacts);
    expect(s.chatKind(10), ChatKind.private);
    expect(s.allows(chatId: 9, media: MediaKind.photos, size: 1), isTrue);
    expect(s.allows(chatId: 10, media: MediaKind.photos, size: 1), isFalse);
    cache.apply(
      td.UpdateNewChat(
        chat: fakeChat(11).copyWith(type: const td.ChatTypeSupergroup(supergroupId: 1, isChannel: true)),
      ),
    );
    cache.apply(
      td.UpdateNewChat(chat: fakeChat(12).copyWith(type: const td.ChatTypeBasicGroup(basicGroupId: 1))),
    );
    expect(s.chatKind(11), ChatKind.channels);
    expect(s.chatKind(12), ChatKind.groups);
    s.dispose();
  });
}
