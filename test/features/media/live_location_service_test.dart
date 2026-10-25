import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib_next/api.dart' as td;
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/media/data/live_location_service.dart';

import '../../helpers/fakes.dart';

class FakePlatform implements LiveLocationPlatform {
  var running = false;
  var allow = true;
  final asked = <bool>[];
  td.Location? here = const td.Location(latitude: 52.52, longitude: 13.405, horizontalAccuracy: 8);

  @override
  Future<bool> begin({bool ask = true}) async {
    asked.add(ask);
    running = allow;
    return allow;
  }

  @override
  Future<void> end() async => running = false;

  @override
  Future<td.Location?> position() async => here;
}

td.Message message(int id, {bool pending = true, int chatId = 7}) {
  final m = fakeMessage(
    id,
    chatId: chatId,
    outgoing: true,
    content: const td.MessageLocation(
      location: td.Location(latitude: 52.52, longitude: 13.405, horizontalAccuracy: 0),
      livePeriod: 900,
      expiresIn: 900,
      heading: 0,
      proximityAlertRadius: 0,
    ),
  );
  return pending ? m.copyWith(sendingState: const td.MessageSendingStatePending(sendingId: 0)) : m;
}

void main() {
  late FakeTdClient client;
  late AppPreferences prefs;
  late FakePlatform platform;
  late DateTime now;

  LiveLocationService service() => LiveLocationService(
    client: client,
    prefs: prefs,
    platform: platform,
    now: () => now,
    interval: Duration.zero,
  );

  setUp(() {
    client = FakeTdClient()..respond = (_) => message(500, pending: false);
    prefs = AppPreferences.inMemory();
    platform = FakePlatform();
    now = DateTime(2026, 10, 25, 12);
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('waits for the real id, then pushes fixes until expiry', () async {
    final s = service();
    expect(await s.prepare(), isTrue);
    s.track(message(-1), 900);
    await s.tick();
    expect(client.sentOf<td.EditMessageLiveLocation>(), isEmpty, reason: 'temporary id');

    client.emitUpdate(td.UpdateMessageSendSucceeded(message: message(500, pending: false), oldMessageId: -1));
    await settle();
    final edits = client.sentOf<td.EditMessageLiveLocation>();
    expect(edits, hasLength(1));
    expect(edits.single.messageId, 500);
    expect(edits.single.location?.latitude, 52.52);

    now = now.add(const Duration(minutes: 16));
    await s.tick();
    expect(s.shares, isEmpty);
    expect(platform.running, isFalse);
  });

  test('skips a fix that barely moved, refreshes after five minutes', () async {
    final s = service();
    s.track(message(500, pending: false), 3600);
    await s.tick();
    platform.here = const td.Location(latitude: 52.52005, longitude: 13.405, horizontalAccuracy: 8); // ~5 m
    now = now.add(const Duration(minutes: 1));
    await s.tick();
    expect(client.sentOf<td.EditMessageLiveLocation>(), hasLength(1));
    platform.here = const td.Location(latitude: 52.521, longitude: 13.405, horizontalAccuracy: 8); // ~110 m
    await s.tick();
    expect(client.sentOf<td.EditMessageLiveLocation>(), hasLength(2));
    now = now.add(const Duration(minutes: 5));
    await s.tick();
    expect(client.sentOf<td.EditMessageLiveLocation>(), hasLength(3));
  });

  test('stopping anywhere (expiresIn 0) ends tracking and the service', () async {
    final s = service();
    s.track(message(500, pending: false), 900);
    expect(platform.running, isTrue);
    client.emitUpdate(
      const td.UpdateMessageContent(
        chatId: 7,
        messageId: 500,
        newContent: td.MessageLocation(
          location: td.Location(latitude: 0, longitude: 0, horizontalAccuracy: 0),
          livePeriod: 900,
          expiresIn: 0,
          heading: 0,
          proximityAlertRadius: 0,
        ),
      ),
    );
    await settle();
    expect(s.shares, isEmpty);
    expect(platform.running, isFalse);
  });

  test('a failed send is dropped', () async {
    final s = service();
    s.track(message(-1), 900);
    client.emitUpdate(
      td.UpdateMessageSendFailed(
        message: message(-1),
        oldMessageId: -1,
        error: const td.TdError(code: 400, message: 'x'),
      ),
    );
    await settle();
    expect(s.shares, isEmpty);
  });

  test('shares resume after a restart without prompting; expired ones do not', () async {
    service()
      ..track(message(500, pending: false), 900)
      ..track(message(501, pending: false, chatId: 8), 60);
    platform = FakePlatform();
    now = now.add(const Duration(minutes: 2));
    final resumed = service();
    expect(resumed.shares.map((s) => s.messageId), [500]);
    expect(platform.asked, [false]);
  });

  test('logout forgets everything', () async {
    final s = service()..track(message(500, pending: false), 900);
    client.emit(const td.AuthorizationStateClosed());
    await settle();
    expect(s.shares, isEmpty);
    expect(prefs.liveLocations, '[]');
  });

  test('distance is great-circle meters', () {
    const a = td.Location(latitude: 0, longitude: 0, horizontalAccuracy: 0);
    const b = td.Location(latitude: 0, longitude: 1, horizontalAccuracy: 0);
    expect(LiveLocationService.distanceMeters(a, b), closeTo(111195, 10));
  });
}
