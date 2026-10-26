import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/folders/bloc/folder_editor_cubit.dart';
import 'package:lumina/features/folders/data/folders_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'folder_draft_test.dart' show folder;
import 'folders_repository_test.dart' show info;

void main() {
  late FakeTdClient client;
  late TelegramCache cache;
  late AppPreferences prefs;
  late FoldersRepository repo;

  setUp(() {
    client = FakeTdClient();
    cache = TelegramCache.detached();
    prefs = AppPreferences.inMemory()..folderColorsJson = '{"3": 6}';
    repo = FoldersRepository(client: client, cache: cache, prefs: prefs);
    client.respond = (f) => switch (f) {
      td.GetChatFolder() => folder(groups: true, included: const [1]).copyWith(colorId: -1),
      td.CreateChatFolder() || td.EditChatFolder() => info(3),
      _ => const td.Ok(),
    };
  });

  test('a new folder is validated before anything is sent', () async {
    final c = FolderEditorCubit(repository: repo, cache: cache);
    await c.load();
    expect(await c.save(), isFalse);
    expect(c.state.error, 'Give the folder a name');
    expect(client.sentOf<td.CreateChatFolder>(), isEmpty);

    c.update((d) => d.copyWith(name: 'Work', includeGroups: true));
    expect(c.state.changed, isTrue);
    expect(await c.save(), isTrue);
    expect(c.state.done, isTrue);
    expect(client.sentOf<td.CreateChatFolder>().single.folder.name.text.text, 'Work');
    await c.close();
  });

  test('editing loads the folder with its local colour and saves by id', () async {
    final c = FolderEditorCubit(repository: repo, cache: cache, folderId: 3);
    await c.load();
    expect(c.state.draft.name, 'Work');
    expect(c.state.draft.colorId, 6);
    c.update((d) => d.copyWith(name: 'Job'));
    await c.save();
    final e = client.sentOf<td.EditChatFolder>().single;
    expect(e.chatFolderId, 3);
    expect(e.folder.name.text.text, 'Job');
    await c.close();
  });

  test('a folder deleted elsewhere closes the editor', () async {
    final c = FolderEditorCubit(repository: repo, cache: cache, folderId: 3);
    await c.load();
    client.respond = (f) => const td.TdError(code: 400, message: 'FILTER_ID_INVALID');
    c.update((d) => d.copyWith(name: 'Job'));
    expect(await c.save(), isFalse);
    expect(c.state.deleted, isTrue);
    expect(c.state.error, 'This folder was deleted');
    await c.close();
  });

  test('convert to a chat list keeps the matching chats', () async {
    cache.apply(
      td.UpdateNewChat(
        chat: fakeChat(8).copyWith(
          positions: const [
            td.ChatPosition(list: td.ChatListFolder(chatFolderId: 3), order: 5, isPinned: false),
          ],
        ),
      ),
    );
    final c = FolderEditorCubit(repository: repo, cache: cache, folderId: 3);
    await c.load();
    c.convertToChatList();
    expect(c.state.draft.hasRules, isFalse);
    expect(c.state.draft.included, [1, 8]);
    await c.close();
  });
}
