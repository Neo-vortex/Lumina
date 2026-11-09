import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/auth/bloc/auth_bloc.dart';
import 'package:lumina/features/conversation/bloc/conversation_cubit.dart';
import 'package:lumina/features/conversation/data/messages_repository.dart';
import 'package:lumina/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:lumina/features/conversation/presentation/widgets/composer.dart';
import 'package:lumina/features/conversation/presentation/widgets/conversation_header.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../helpers/fakes.dart';

void main() {
  testWidgets('a new message rebuilds the list, not the header or composer', (tester) async {
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
    // Let the screen settle (the list is revealed a frame after it lands, the
    // composer's height is measured): those rebuild it once, by design.
    await tester.pump(const Duration(seconds: 1));

    final header = tester.widget(find.byType(ConversationHeader));
    final composer = tester.widget(find.byType(Composer));

    client.emitUpdate(td.UpdateNewMessage(message: fakeMessage(3, date: 1761390180)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('hi'), findsNWidgets(3));
    expect(identical(tester.widget(find.byType(ConversationHeader)), header), isTrue);
    expect(identical(tester.widget(find.byType(Composer)), composer), isTrue);
    // The new message is reported read (debounced) now that it's on screen.
    await tester.pump(const Duration(milliseconds: 500));
    expect(client.sent.whereType<td.ViewMessages>().any((v) => v.messageIds.contains(3)), isTrue);

    await tester.pumpWidget(const SizedBox());
  });
}
