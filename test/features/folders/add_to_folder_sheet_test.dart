import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/folders/data/folders_repository.dart';
import 'package:lumina/features/folders/presentation/widgets/add_to_folder_sheet.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'folder_draft_test.dart' show folder;
import 'folders_repository_test.dart' show info;

void main() {
  testWidgets('ticks add with addChatToList, unticks edit the folder', (tester) async {
    final client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetChatListsToAddChat() => const td.ChatLists(chatLists: [td.ChatListFolder(chatFolderId: 3)]),
        td.GetChatFolder() => folder(included: const [1]),
        td.EditChatFolder() => info(5),
        _ => const td.Ok(),
      };
    final cache = TelegramCache.detached()
      ..apply(
        td.UpdateChatFolders(chatFolders: [info(3), info(5)], mainChatListPosition: 0, areTagsEnabled: false),
      )
      ..apply(
        td.UpdateNewChat(
          chat: fakeChat(1).copyWith(
            positions: const [
              td.ChatPosition(list: td.ChatListFolder(chatFolderId: 5), order: 3, isPinned: false),
            ],
          ),
        ),
      );
    final repo = FoldersRepository(client: client, cache: cache, prefs: AppPreferences.inMemory());
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: cache),
          RepositoryProvider.value(value: repo),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAddToFolderSheet(context, cache.chats[1]!),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('F3'));
    await tester.pumpAndSettle();
    expect(client.sentOf<td.AddChatToList>().single.chatId, 1);
    await tester.tap(find.text('F5'));
    await tester.pumpAndSettle();
    expect(client.sentOf<td.EditChatFolder>().single.folder.excludedChatIds, [1]);
  });
}
