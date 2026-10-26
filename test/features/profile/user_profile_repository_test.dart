import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/profile/data/user_profile_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

void main() {
  test('block and unblock go to the main block list', () async {
    final client = FakeTdClient();
    final repo = UserProfileRepository(client);
    await repo.setBlocked(42, true);
    await repo.setBlocked(42, false);
    final sent = client.sentOf<td.SetMessageSenderBlockList>();
    expect(sent.first.blockList, isA<td.BlockListMain>());
    expect(sent.last.blockList, isNull);
    expect((sent.first.senderId as td.MessageSenderUser).userId, 42);
  });

  test('each tab searches the private chat with its own filter', () async {
    final client = FakeTdClient()
      ..respond = (_) => const td.FoundChatMessages(totalCount: 0, messages: [], nextFromMessageId: 0);
    final repo = UserProfileRepository(client);
    await repo.shared(42, ProfileTab.links);
    await repo.shared(42, ProfileTab.music);
    final sent = client.sentOf<td.SearchChatMessages>();
    expect(sent[0].filter, isA<td.SearchMessagesFilterUrl>());
    expect(sent[1].filter, isA<td.SearchMessagesFilterAudio>());
    expect(sent.every((s) => s.chatId == 42), isTrue);
  });

  test('deleting removes the contact; renaming re-adds it with the new name', () async {
    final client = FakeTdClient();
    final repo = UserProfileRepository(client);
    await repo.deleteContact(42);
    await repo.saveContact(fakeUser(), firstName: 'Ada', lastName: 'L');
    expect(client.sentOf<td.RemoveContacts>().single.userIds, [42]);
    expect(client.sentOf<td.AddContact>().single.contact.firstName, 'Ada');
  });
}
