import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/conversation/data/messages_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

void main() {
  final now = DateTime(2026, 10, 26, 18);
  int unix(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  Future<String?> status(td.TdObject answer) => MessagesRepository(
    client: FakeTdClient()..respond = (_) => answer,
    prefs: AppPreferences.inMemory(),
  ).readStatus(1, 2, now: now);

  test('read status reads like Telegram', () async {
    expect(
      await status(td.MessageReadDateRead(readDate: unix(DateTime(2026, 10, 26, 14, 2)))),
      'Read today at 14:02',
    );
    expect(
      await status(td.MessageReadDateRead(readDate: unix(DateTime(2026, 10, 25, 9, 5)))),
      'Read yesterday at 09:05',
    );
    expect(
      await status(td.MessageReadDateRead(readDate: unix(DateTime(2026, 10, 3, 20, 0)))),
      'Read 3 Oct at 20:00',
    );
    expect(await status(const td.MessageReadDateUnread()), 'Not read yet');
    expect(await status(const td.MessageReadDateTooOld()), isNull);
  });
}
