import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/folders/bloc/join_folder_cubit.dart';
import 'package:lumina/features/folders/data/folders_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'folders_repository_test.dart' show info;

void main() {
  late FakeTdClient client;
  late TelegramCache cache;
  late FoldersRepository repo;

  setUp(() {
    client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.CheckChatFolderInviteLink() => td.ChatFolderInviteLinkInfo(
          chatFolderInfo: info(0),
          missingChatIds: const [1, 2],
          addedChatIds: const [3],
        ),
        _ => const td.Ok(),
      };
    cache = TelegramCache.detached()
      ..apply(td.UpdateChatFolders(chatFolders: [info(7)], mainChatListPosition: 0, areTagsEnabled: false));
    repo = FoldersRepository(client: client, cache: cache, prefs: AppPreferences.inMemory());
  });

  test('a link preselects the chats to join and adds the folder', () async {
    final c = JoinFolderCubit.link(repository: repo, url: 'https://t.me/addlist/abc');
    await c.load();
    expect(c.state.title, 'F0');
    expect(c.state.existing, isFalse);
    expect(c.state.chatIds, [1, 2, 3]);
    expect(c.state.alreadyIn, {3});
    expect(c.state.selected, {1, 2});
    c.toggle(2);
    c.toggle(3); // already in: ignored
    await c.join();
    final j = client.sentOf<td.AddChatFolderByInviteLink>().single;
    expect(j.inviteLink, 'https://t.me/addlist/abc');
    expect(j.chatIds, [1]);
    expect(c.state.done, isTrue);
  });

  test('an expired link shows why', () async {
    client.respond = (_) => const td.TdError(code: 400, message: 'INVITE_SLUG_EXPIRED');
    final c = JoinFolderCubit.link(repository: repo, url: 'https://t.me/addlist/old');
    await c.load();
    expect(c.state.error, 'This folder link has expired');
  });

  test('new chats: join the ticked ones, or dismiss them all', () async {
    final c = JoinFolderCubit.newChats(repository: repo, cache: cache, folderId: 7, chatIds: const [11, 12]);
    await c.load();
    expect(c.state.title, 'F7');
    c.toggle(12);
    await c.join();
    expect(client.sentOf<td.ProcessChatFolderNewChats>().single.addedChatIds, [11]);

    final d = JoinFolderCubit.newChats(repository: repo, cache: cache, folderId: 7, chatIds: const [11]);
    await d.load();
    await d.notNow();
    expect(client.sentOf<td.ProcessChatFolderNewChats>().last.addedChatIds, isEmpty);
  });
}
