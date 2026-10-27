import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/auth/bloc/auth_bloc.dart';
import 'package:lumina/features/conversation/bloc/conversation_cubit.dart';
import 'package:lumina/features/conversation/data/messages_repository.dart';
import 'package:lumina/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:lumina/features/conversation/presentation/widgets/conversation_extensions.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../helpers/fakes.dart';

class _Welcome extends ConversationExtensions {
  const _Welcome();

  @override
  Widget? emptyChat(BuildContext context, td.Chat chat) => const Text('WELCOME');
}

void main() {
  for (final empty in [true, false]) {
    testWidgets('the empty-chat hook shows only while there are no messages (empty: $empty)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final client = FakeTdClient()
        ..respond = (f) => switch (f) {
          td.GetChatHistory(fromMessageId: 0) => td.Messages(
            totalCount: empty ? 0 : 1,
            messages: empty ? const [] : [fakeMessage(1)],
          ),
          td.GetChatHistory() => const td.Messages(totalCount: 0, messages: []),
          td.GetChatPinnedMessage() ||
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
            RepositoryProvider<ConversationExtensions>.value(value: const _Welcome()),
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
      expect(find.text('WELCOME'), empty ? findsOneWidget : findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
