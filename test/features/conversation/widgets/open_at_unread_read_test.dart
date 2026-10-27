import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/auth/bloc/auth_bloc.dart';
import 'package:lumina/features/conversation/bloc/conversation_cubit.dart';
import 'package:lumina/features/conversation/data/messages_repository.dart';
import 'package:lumina/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../helpers/fakes.dart';

void main() {
  testWidgets('opening at the first unread never marks the bottom of the loaded window read first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final viewed = <List<int>>[];
    final client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetChatHistory(:final fromMessageId) when fromMessageId == 50 => td.Messages(
          totalCount: 50,
          messages: [for (var id = 75; id > 25; id--) fakeMessage(id, date: 1761390000 + id * 60)],
        ),
        td.GetChatHistory() => const td.Messages(totalCount: 0, messages: []),
        td.ViewMessages(:final messageIds) => (() {
          viewed.add(messageIds);
          return const td.Ok();
        })(),
        td.GetChatPinnedMessage() => const td.TdError(code: 404, message: 'Not Found'),
        td.GetMessageProperties() ||
        td.GetMessageAvailableReactions() ||
        td.GetEmojiReaction() => const td.TdError(code: 404, message: 'Not Found'),
        _ => const td.Ok(),
      };
    final prefs = AppPreferences.inMemory();
    final cache = TelegramCache.detached()
      ..apply(
        td.UpdateNewChat(
          chat: fakeChat(
            1,
            order: 5,
            unread: 50,
            lastMessage: fakeMessage(100),
          ).copyWith(lastReadInboxMessageId: 50),
        ),
      );
    final cubit = ConversationCubit(
      chatId: 1,
      repository: MessagesRepository(client: client, prefs: prefs),
      cache: cache,
      updates: client.updates,
    );
    final auth = AuthBloc(repository: AuthHarness().repository);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: cache),
          RepositoryProvider.value(value: prefs),
          RepositoryProvider(
            create: (_) => MessagesRepository(client: client, prefs: prefs),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: auth),
            BlocProvider.value(value: cubit),
          ],
          child: const MaterialApp(home: ConversationScreen()),
        ),
      ),
    );
    // As the route does: the screen is up before the window loads.
    await cubit.start();
    expect(cubit.state.firstUnreadId, 51);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(viewed, isNotEmpty);
    expect(viewed.first, contains(51), reason: 'the first unread is on screen when reading starts');
    expect(viewed.expand((ids) => ids), isNot(contains(75)), reason: 'the window bottom was never on screen');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
