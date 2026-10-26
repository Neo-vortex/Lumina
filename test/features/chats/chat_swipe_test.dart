import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/gestures/swipe_actions.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/chats/data/chats_repository.dart';
import 'package:lumina/features/chats/presentation/widgets/chat_swipe.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

void main() {
  Future<FakeTdClient> pump(WidgetTester tester, AppPreferences prefs) async {
    final client = FakeTdClient();
    final cache = TelegramCache.detached()..apply(td.UpdateNewChat(chat: fakeChat(1, title: 'Ada')));
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: prefs),
          RepositoryProvider.value(value: cache),
          RepositoryProvider(
            create: (_) => ChatsRepository(client: client, cache: cache),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SwipeableChatRow(
              chat: cache.chats[1]!,
              child: const SizedBox(height: 72, child: Center(child: Text('Ada row'))),
            ),
          ),
        ),
      ),
    );
    return client;
  }

  testWidgets('swiping right pins and swiping left archives (defaults)', (tester) async {
    final client = await pump(tester, AppPreferences.inMemory());
    await tester.drag(find.text('Ada row'), const Offset(200, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(client.sentOf<td.ToggleChatIsPinned>().single.isPinned, isTrue);

    await tester.drag(find.text('Ada row'), const Offset(-200, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(client.sentOf<td.AddChatToList>().single.chatList, isA<td.ChatListArchive>());
  });

  testWidgets('a delete swipe confirms first and deletes nothing when cancelled', (tester) async {
    final prefs = AppPreferences.inMemory()..setChatSwipe(SwipeSide.right, ChatSwipe.delete);
    final client = await pump(tester, prefs);
    await tester.drag(find.text('Ada row'), const Offset(200, 0));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Delete chat with Ada?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(client.sentOf<td.DeleteChatHistory>(), isEmpty);
  });

  testWidgets('a swipe starting at the screen edge is left for the folder pages', (tester) async {
    final client = await pump(tester, AppPreferences.inMemory());
    final y = tester.getCenter(find.text("Ada row")).dy;
    await tester.dragFrom(Offset(10, y), const Offset(200, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(client.sentOf<td.ToggleChatIsPinned>(), isEmpty);
  });
}
