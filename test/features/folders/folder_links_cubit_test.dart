import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/folders/bloc/folder_links_cubit.dart';
import 'package:lumina/features/folders/data/folders_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'folder_draft_test.dart' show folder;
import 'folders_repository_test.dart' show info;

const link = td.ChatFolderInviteLink(inviteLink: 'https://t.me/addlist/abc', name: 'Team', chatIds: [1, 2]);

void main() {
  late FakeTdClient client;
  late FoldersRepository repo;
  late TelegramCache cache;
  var withRules = false;

  setUp(() {
    withRules = false;
    client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetChatFolder() =>
          withRules ? folder(groups: true, included: const [1]) : folder(included: const [1, 2]),
        td.GetChatFolderInviteLinks() => const td.ChatFolderInviteLinks(inviteLinks: [link]),
        td.GetChatsForChatFolderInviteLink() => const td.Chats(totalCount: 2, chatIds: [1, 2]),
        td.CreateChatFolderInviteLink() => link,
        td.EditChatFolder() => info(3),
        _ => const td.Ok(),
      };
    cache = TelegramCache.detached();
    repo = FoldersRepository(client: client, cache: cache, prefs: AppPreferences.inMemory());
  });

  test('a shareable folder loads its links and shareable chats', () async {
    final c = FolderLinksCubit(repository: repo, cache: cache, folderId: 3);
    await c.load();
    expect(c.state.needsConversion, isFalse);
    expect(c.state.links.single.name, 'Team');
    expect(c.state.shareable, [1, 2]);
    await c.close();
  });

  test('a folder with rules asks to convert first, then converts', () async {
    withRules = true;
    final c = FolderLinksCubit(repository: repo, cache: cache, folderId: 3);
    await c.load();
    expect(c.state.needsConversion, isTrue);
    expect(client.sentOf<td.GetChatFolderInviteLinks>(), isEmpty);
    withRules = false;
    await c.convert();
    final edited = client.sentOf<td.EditChatFolder>().single.folder;
    expect(edited.includeGroups, isFalse);
    expect(c.state.needsConversion, isFalse);
    await c.close();
  });

  test('create and delete', () async {
    final c = FolderLinksCubit(repository: repo, cache: cache, folderId: 3);
    await c.load();
    await c.create('Team', const [1, 2]);
    expect(client.sentOf<td.CreateChatFolderInviteLink>().single.chatIds, [1, 2]);
    await c.delete(link);
    expect(client.sentOf<td.DeleteChatFolderInviteLink>().single.inviteLink, link.inviteLink);
    await c.close();
  });
}
