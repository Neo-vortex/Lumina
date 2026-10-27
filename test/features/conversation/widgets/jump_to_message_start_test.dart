import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
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
  testWidgets('jumping to a tall message (pinned banner) shows its start, not its middle', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final tall = 'START ${List.filled(400, 'word').join(' ')} END';
    final client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetChatHistory(fromMessageId: 0) => td.Messages(
          totalCount: 60,
          messages: [
            for (var id = 60; id > 0; id--)
              fakeMessage(id, date: 1761390000 + id * 60, text: id == 20 ? tall : 'message $id'),
          ],
        ),
        td.GetChatHistory() => const td.Messages(totalCount: 0, messages: []),
        td.GetChatPinnedMessage() => const td.TdError(code: 404, message: 'Not Found'),
        td.GetMessageProperties() ||
        td.GetMessageAvailableReactions() ||
        td.GetEmojiReaction() => const td.TdError(code: 404, message: 'Not Found'),
        _ => const td.Ok(),
      };
    final prefs = AppPreferences.inMemory();
    final cache = TelegramCache.detached()
      ..apply(td.UpdateNewChat(chat: fakeChat(1, order: 5, lastMessage: fakeMessage(60))));
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
    await cubit.start();
    await tester.pump(const Duration(milliseconds: 100));

    await cubit.jumpTo(20);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final list = tester.getRect(find.byType(SuperListView));
    final bubble = tester.getRect(
      find.ancestor(
        of: find.textContaining('START', findRichText: true),
        matching: find.byType(MessageBubble),
      ),
    );
    expect(bubble.height, greaterThan(list.height / 2), reason: 'the case being tested');
    expect(bubble.top, greaterThanOrEqualTo(list.top), reason: 'the start is on screen');
    expect(bubble.top, lessThan(list.top + list.height / 3), reason: 'and near the top, room for the rest');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
