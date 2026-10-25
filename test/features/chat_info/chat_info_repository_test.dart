import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/chat_info/data/chat_info_repository.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeTdClient client;
  late ChatInfoRepository repo;

  setUp(() {
    client = FakeTdClient();
    repo = ChatInfoRepository(client: client, cache: TelegramCache.detached());
  });

  test('createGroup creates the basic group, then loads its chat', () async {
    client.respond = (f) => switch (f) {
      td.CreateNewBasicGroupChat() => const td.CreatedBasicGroupChat(
        chatId: -42,
        failedToAddMembers: td.FailedToAddMembers(failedToAddMembers: []),
      ),
      td.GetChat(:final chatId) => fakeChat(chatId, title: 'Team'),
      _ => const td.Ok(),
    };
    final chat = await repo.createGroup('Team', [1, 2]);
    expect(chat.id, -42);
    final create = client.sentOf<td.CreateNewBasicGroupChat>().single;
    expect(create.title, 'Team');
    expect(create.userIds, [1, 2]);
  });

  test('findUser resolves @username to a private chat user', () async {
    client.respond = (f) => fakeChat(77);
    expect(await repo.findUser('@alice'), 77);
    expect(client.sentOf<td.SearchPublicChat>().single.username, 'alice');
  });

  test('findUser returns null for unknown usernames', () async {
    client.respond = (f) => const td.TdError(code: 400, message: 'USERNAME_NOT_OCCUPIED');
    expect(await repo.findUser('nobody'), isNull);
  });
}
