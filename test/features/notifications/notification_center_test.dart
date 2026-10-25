import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib_next/api.dart' as td;
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/notifications/data/notification_center.dart';

import '../../helpers/fakes.dart';

class FakeSink implements NotificationSink {
  final shown = <Map<String, Object?>>[];
  final cancelled = <int>[];
  var cancelledAll = false;
  final _actions = StreamController<Map<Object?, Object?>>.broadcast();

  void act(Map<Object?, Object?> a) => _actions.add(a);

  @override
  Future<void> show(Map<String, Object?> n) async => shown.add(n);

  @override
  Future<void> cancel(int id) async => cancelled.add(id);

  @override
  Future<void> cancelAll() async => cancelledAll = true;

  @override
  Stream<Map<Object?, Object?>> get actions => _actions.stream;
}

td.Notification note(int id, int messageId, {bool silent = false, String text = 'hi'}) => td.Notification(
  id: id,
  date: 0,
  isSilent: silent,
  type: td.NotificationTypeNewMessage(
    message: fakeMessage(messageId, chatId: 1, text: text),
    showPreview: true,
  ),
);

td.UpdateNotificationGroup group({List<td.Notification> added = const [], List<int> removed = const []}) =>
    td.UpdateNotificationGroup(
      notificationGroupId: 77,
      type: const td.NotificationGroupTypeMessages(),
      chatId: 1,
      notificationSettingsChatId: 1,
      notificationSoundId: 0,
      totalCount: added.length,
      addedNotifications: added,
      removedNotificationIds: removed,
    );

void main() {
  late FakeTdClient client;
  late FakeSink sink;
  late NotificationCenter center;
  var foreground = false;
  final opened = <int>[];

  setUp(() {
    client = FakeTdClient();
    sink = FakeSink();
    foreground = false;
    opened.clear();
    center = NotificationCenter(
      client: client,
      cache: TelegramCache(client),
      sink: sink,
      openChat: opened.add,
      foreground: () => foreground,
    );
  });

  tearDown(() => center.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('asks TDLib for notification groups once logged in', () async {
    client.emit(const td.AuthorizationStateReady());
    await settle();
    final names = client.sentOf<td.SetOption>().map((o) => o.name);
    expect(names, containsAll(['notification_group_count_max', 'notification_group_size_max']));
  });

  test('new messages are shown per group; silent ones stay silent', () async {
    client.emitUpdate(
      group(
        added: [
          note(1, 10, text: 'one'),
          note(2, 11, silent: true, text: 'two'),
        ],
      ),
    );
    await settle();
    final n = sink.shown.single;
    expect((n['id'], n['chatId'], n['alert'], n['silent']), (77, 1, true, false));
    expect((n['messages']! as List).map((m) => (m as Map)['text']), ['one', 'two']);

    client.emitUpdate(group(added: [note(3, 12, silent: true)]));
    await settle();
    expect(sink.shown.last['alert'], isFalse);
  });

  test('read elsewhere: TDLib removes them, the notification goes', () async {
    client.emitUpdate(group(added: [note(1, 10)]));
    client.emitUpdate(group(removed: [1]));
    await settle();
    expect(sink.cancelled, [77]);
  });

  test('nothing is posted while Lumina is in the foreground', () async {
    foreground = true;
    client.emitUpdate(group(added: [note(1, 10)]));
    await settle();
    expect(sink.shown, isEmpty);
  });

  test('reply sends the text and marks the shown messages read', () async {
    client.respond = (f) => f is td.SendMessage ? fakeMessage(99, chatId: 1) : const td.Ok();
    client.emitUpdate(group(added: [note(1, 10), note(2, 14)]));
    await settle();
    sink.act({'type': 'reply', 'chatId': 1, 'groupId': 77, 'text': ' on my way '});
    await settle();
    await settle();
    final sent = client.sentOf<td.SendMessage>().single;
    expect((sent.inputMessageContent as td.InputMessageText).text.text, 'on my way');
    final view = client.sentOf<td.ViewMessages>().single;
    expect((view.chatId, view.forceRead), (1, true));
    expect(view.messageIds, [14]);
  });

  test('mark as read after a cold start uses the chat\'s last message', () async {
    client.respond = (f) =>
        f is td.GetChat ? fakeChat(1, lastMessage: fakeMessage(50, chatId: 1)) : const td.Ok();
    sink.act({'type': 'read', 'chatId': 1, 'groupId': 5});
    await settle();
    await settle();
    expect(client.sentOf<td.ViewMessages>().single.messageIds, [50]);
  });

  test('tapping opens the chat; logout clears everything', () async {
    sink.act({'type': 'open', 'chatId': 1});
    await settle();
    expect(opened, [1]);
    client.emit(const td.AuthorizationStateClosed());
    await settle();
    expect(sink.cancelledAll, isTrue);
  });
}
