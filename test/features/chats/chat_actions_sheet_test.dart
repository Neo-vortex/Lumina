import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/chats/data/chats_repository.dart';
import 'package:lumina/features/chats/presentation/widgets/chat_actions_sheet.dart';
import 'package:lumina/features/chats/presentation/widgets/chat_list_extensions.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

class _Ext extends ChatListExtensions {
  _Ext(this.ran);
  final List<int> ran;

  @override
  List<ChatAction> chatActions(td.Chat chat) => [
    ChatAction(label: 'Add to folder…', icon: Icons.folder_rounded, run: (_) async => ran.add(chat.id)),
  ];
}

void main() {
  testWidgets('pins within the shown list and offers hook actions', (tester) async {
    final client = FakeTdClient();
    final cache = TelegramCache.detached()..apply(td.UpdateNewChat(chat: fakeChat(1, order: 5)));
    final ran = <int>[];
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: cache),
          RepositoryProvider.value(
            value: ChatsRepository(client: client, cache: cache),
          ),
          RepositoryProvider<ChatListExtensions>.value(value: _Ext(ran)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showChatActions(context, cache.chats[1]!, list: const td.ChatListFolder(chatFolderId: 3)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();
    final pin = client.sentOf<td.ToggleChatIsPinned>().single;
    expect((pin.chatList as td.ChatListFolder).chatFolderId, 3);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to folder…'));
    await tester.pumpAndSettle();
    expect(ran, [1]);
  });
}
