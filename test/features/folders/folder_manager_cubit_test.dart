import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/folders/bloc/folder_manager_cubit.dart';
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
        td.GetRecommendedChatFolders() => const td.RecommendedChatFolders(chatFolders: []),
        _ => const td.Ok(),
      };
    cache = TelegramCache.detached()
      ..apply(
        td.UpdateChatFolders(chatFolders: [info(3), info(5)], mainChatListPosition: 0, areTagsEnabled: false),
      );
    repo = FoldersRepository(client: client, cache: cache, prefs: AppPreferences.inMemory());
  });

  Future<void> premium() async {
    client.emitUpdate(const td.UpdateOption(name: 'is_premium', value: td.OptionValueBoolean(value: true)));
    await Future<void>.delayed(Duration.zero);
  }

  test('rows put All chats at its position', () async {
    final c = FolderManagerCubit(repository: repo, cache: cache);
    await c.load();
    expect(c.state.rows.map((r) => r.folder?.id), [null, 3, 5]);
    await c.close();
  });

  test('reorder keeps All chats where it was dropped', () async {
    await premium();
    final c = FolderManagerCubit(repository: repo, cache: cache);
    await c.load();
    await c.reorder(0, 2); // ReorderableListView: drop All chats after "3"
    final r = client.sentOf<td.ReorderChatFolders>().single;
    expect(r.chatFolderIds, [3, 5]);
    expect(r.mainChatListPosition, 1);
    expect(c.state.rows.map((r) => r.folder?.id), [3, null, 5]);
    await c.close();
  });

  test('without Premium All chats stays first', () async {
    final c = FolderManagerCubit(repository: repo, cache: cache);
    await c.load();
    await c.reorder(0, 2);
    expect(client.sentOf<td.ReorderChatFolders>(), isEmpty);
    expect(c.state.error, 'Moving All chats needs Telegram Premium');
    expect(c.state.rows.map((r) => r.folder?.id), [null, 3, 5]);
    await c.close();
  });

  test('folders reorder without Premium', () async {
    final c = FolderManagerCubit(repository: repo, cache: cache);
    await c.load();
    await c.reorder(2, 1);
    final r = client.sentOf<td.ReorderChatFolders>().single;
    expect(r.chatFolderIds, [5, 3]);
    expect(r.mainChatListPosition, 0);
    await c.close();
  });

  test('delete passes the chats to leave', () async {
    final c = FolderManagerCubit(repository: repo, cache: cache);
    await c.delete(5, leave: const [9]);
    final d = client.sentOf<td.DeleteChatFolder>().single;
    expect(d.chatFolderId, 5);
    expect(d.leaveChatIds, [9]);
    await c.close();
  });
}
