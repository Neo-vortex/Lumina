import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/auth/bloc/auth_bloc.dart';
import 'package:lumina/features/conversation/bloc/conversation_cubit.dart';
import 'package:lumina/features/conversation/data/messages_repository.dart';
import 'package:lumina/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:lumina/features/conversation/presentation/widgets/message_bubble.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../helpers/fakes.dart';

void main() {
  testWidgets('a sent message keeps its bubble when TDLib swaps in the server id (no double insert)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetChatHistory(fromMessageId: 0) => td.Messages(
          totalCount: 2,
          messages: [fakeMessage(2, date: 1761390060), fakeMessage(1)],
        ),
        td.GetChatHistory() => const td.Messages(totalCount: 0, messages: []),
        td.GetChatPinnedMessage() => const td.TdError(code: 404, message: 'Not Found'),
        td.GetMessageProperties() ||
        td.GetMessageAvailableReactions() ||
        td.GetEmojiReaction() => const td.TdError(code: 404, message: 'Not Found'),
        _ => const td.Ok(),
      };
    final prefs = AppPreferences.inMemory();
    final cache = TelegramCache.detached()..apply(td.UpdateNewChat(chat: fakeChat(1, order: 5)));
    final cubit = ConversationCubit(
      chatId: 1,
      repository: MessagesRepository(client: client, prefs: prefs),
      cache: cache,
      updates: client.updates,
    );
    final auth = AuthBloc(repository: AuthHarness().repository);
    await cubit.start();

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
    await tester.pump();

    final pending = fakeMessage(1000, outgoing: true, text: 'sent now', date: 1761390300);
    client.emitUpdate(td.UpdateNewMessage(message: pending));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final before = tester.state(
      find.ancestor(of: find.text('sent now'), matching: find.byType(MessageBubble)),
    );

    client.emitUpdate(
      td.UpdateMessageSendSucceeded(
        message: fakeMessage(50, outgoing: true, text: 'sent now', date: 1761390300),
        oldMessageId: 1000,
      ),
    );
    await tester.pump();
    final after = tester.state(
      find.ancestor(of: find.text('sent now'), matching: find.byType(MessageBubble)),
    );
    expect(identical(before, after), isTrue);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
  });
}
