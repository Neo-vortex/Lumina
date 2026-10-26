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
  testWidgets(
    'a bubble that already animated in does not replay its entrance when the next message lands (G1)',
    (tester) async {
      final client = FakeTdClient()
        ..respond = (f) => switch (f) {
          td.GetChatHistory(fromMessageId: 0) => td.Messages(
            totalCount: 2,
            messages: [fakeMessage(2, date: 1761390060), fakeMessage(1)],
          ),
          td.GetChatHistory() => const td.Messages(totalCount: 0, messages: []),
          td.GetChatPinnedMessage() => const td.TdError(code: 404, message: 'Not Found'),
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

      Future<void> arrive(int id) async {
        client.emitUpdate(td.UpdateNewMessage(message: fakeMessage(id, date: 1761390000 + id * 60)));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }

      await arrive(3);

      // Right after the next arrival, bubble 3 is fully shown, not replaying.
      client.emitUpdate(td.UpdateNewMessage(message: fakeMessage(4, date: 1761390240)));
      await tester.pump();
      expect(find.byType(MessageBubble), findsNWidgets(4));
      final fade = tester.widget<FadeTransition>(
        find.descendant(of: find.byKey(const ValueKey(3)), matching: find.byType(FadeTransition)).first,
      );
      expect(fade.opacity.value, 1);

      await tester.pumpWidget(const SizedBox());
    },
  );
}
