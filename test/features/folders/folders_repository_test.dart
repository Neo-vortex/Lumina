import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/folders/data/folders_repository.dart';
import 'package:lumina/features/folders/domain/folder_draft.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'folder_draft_test.dart' show folder;

td.ChatFolderInfo info(int id, {int colorId = -1, bool shareable = false, bool mine = false}) =>
    td.ChatFolderInfo(
      id: id,
      name: td.ChatFolderName(
        text: td.FormattedText(text: 'F$id', entities: const []),
        animateCustomEmoji: false,
      ),
      icon: const td.ChatFolderIcon(name: 'Custom'),
      colorId: colorId,
      isShareable: shareable,
      hasMyInviteLinks: mine,
    );

void main() {
  late FakeTdClient client;
  late TelegramCache cache;
  late AppPreferences prefs;
  late FoldersRepository repo;
  var now = DateTime(2026, 10, 26, 12);

  setUp(() {
    client = FakeTdClient();
    cache = TelegramCache.detached();
    prefs = AppPreferences.inMemory();
    now = DateTime(2026, 10, 26, 12);
    repo = FoldersRepository(client: client, cache: cache, prefs: prefs, now: () => now);
    client.respond = (f) => switch (f) {
      td.CreateChatFolder() || td.EditChatFolder() => info(7),
      td.GetChatFolder() => folder(groups: true, included: const [1]),
      td.GetChatFolderNewChats() => const td.Chats(totalCount: 2, chatIds: [11, 12]),
      _ => const td.Ok(),
    };
  });

  final draft = const FolderDraft.empty().copyWith(name: 'Work', includeGroups: true, colorId: 4);

  test('non-Premium colour is stored locally and not sent', () async {
    final created = await repo.create(draft);
    expect(client.sentOf<td.CreateChatFolder>().single.folder.colorId, -1);
    expect(repo.localColor(created.id), 4);
    expect(repo.colorIdOf(info(7)), 4);
  });

  test('Premium colour is sent to Telegram', () async {
    client.emitUpdate(const td.UpdateOption(name: 'is_premium', value: td.OptionValueBoolean(value: true)));
    await Future<void>.delayed(Duration.zero);
    await repo.create(draft);
    expect(client.sentOf<td.CreateChatFolder>().single.folder.colorId, 4);
    expect(repo.colorIdOf(info(7, colorId: 1)), 1);
  });

  test('adding a chat uses addChatToList', () async {
    await repo.setChatInFolder(5, 3, inFolder: true);
    final sent = client.sentOf<td.AddChatToList>().single;
    expect((sent.chatId, (sent.chatList as td.ChatListFolder).chatFolderId), (5, 3));
  });

  test('removing a chat that a rule includes excludes it', () async {
    await repo.setChatInFolder(1, 3, inFolder: false);
    final edit = client.sentOf<td.EditChatFolder>().single;
    expect(edit.chatFolderId, 3);
    expect(edit.folder.includedChatIds, isEmpty);
    expect(edit.folder.excludedChatIds, [1]);
  });

  test('new chats are checked only for joined shared folders, at most every 10 minutes', () async {
    cache.apply(
      td.UpdateChatFolders(
        chatFolders: [info(1), info(2, shareable: true), info(3, shareable: true, mine: true)],
        mainChatListPosition: 0,
        areTagsEnabled: false,
      ),
    );
    await repo.refreshNewChats();
    expect(client.sentOf<td.GetChatFolderNewChats>().map((f) => f.chatFolderId), [2]);
    expect(repo.newChats.value, {
      2: [11, 12],
    });

    await repo.refreshNewChats();
    expect(client.sentOf<td.GetChatFolderNewChats>(), hasLength(1));
    now = now.add(const Duration(minutes: 11));
    await repo.refreshNewChats();
    expect(client.sentOf<td.GetChatFolderNewChats>(), hasLength(2));
  });

  test('processing new chats clears the count', () async {
    cache.apply(
      td.UpdateChatFolders(
        chatFolders: [info(2, shareable: true)],
        mainChatListPosition: 0,
        areTagsEnabled: false,
      ),
    );
    await repo.refreshNewChats();
    await repo.processNewChats(2, const [11]);
    expect(client.sentOf<td.ProcessChatFolderNewChats>().single.addedChatIds, [11]);
    expect(repo.newChats.value, isEmpty);
  });

  test('reorder sends the folder order and where All chats goes', () async {
    await repo.reorder(const [5, 3], 1);
    final r = client.sentOf<td.ReorderChatFolders>().single;
    expect(r.chatFolderIds, [5, 3]);
    expect(r.mainChatListPosition, 1);
  });
}
