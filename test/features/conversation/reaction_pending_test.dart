import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/conversation/bloc/conversation_cubit.dart';
import 'package:lumina/features/conversation/data/messages_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'reaction_emoji_test.dart' show available;

td.MessageInteractionInfo hearts(int count, {bool mine = false}) => td.MessageInteractionInfo(
  viewCount: 0,
  forwardCount: 0,
  reactions: td.MessageReactions(
    reactions: [
      td.MessageReaction(
        type: const td.ReactionTypeEmoji(emoji: '❤'),
        totalCount: count,
        isChosen: mine,
        recentSenderIds: const [],
      ),
    ],
    areTags: false,
    paidReactors: const [],
    canGetAddedReactions: false,
  ),
);

void main() {
  late FakeTdClient client;
  late Completer<td.TdObject> answer;
  late ConversationCubit cubit;

  setUp(() async {
    answer = Completer();
    client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetChatHistory(fromMessageId: 0) => td.Messages(totalCount: 1, messages: [fakeMessage(5)]),
        td.GetChatHistory() => const td.Messages(totalCount: 0, messages: []),
        td.GetMessageAvailableReactions() => available(['❤']),
        td.AddMessageReaction() => answer.future,
        td.GetChatPinnedMessage() => const td.TdError(code: 404, message: 'Not Found'),
        _ => const td.Ok(),
      };
    cubit = ConversationCubit(
      chatId: 1,
      repository: MessagesRepository(client: client, prefs: AppPreferences.inMemory()),
      cache: TelegramCache.detached()..apply(td.UpdateNewChat(chat: fakeChat(1))),
      updates: client.updates,
    );
    await cubit.start();
  });

  tearDown(() => cubit.close());

  int? count() => cubit.state.messages.single.interactionInfo?.reactions?.reactions.single.totalCount;

  test('pending: the chip glows and TDLib\'s early count waits for the answer', () async {
    final done = cubit.toggleReaction(cubit.state.messages.single, '❤️');
    await pumpEventQueue();
    expect(cubit.isReactionPending(5, '❤️'), isTrue);
    client.emitUpdate(
      td.UpdateMessageInteractionInfo(chatId: 1, messageId: 5, interactionInfo: hearts(1, mine: true)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(count(), isNull, reason: 'nothing applied before the API answers');

    answer.complete(const td.Ok());
    expect(await done, isTrue);
    expect(cubit.isReactionPending(5, '❤'), isFalse);
    expect(count(), 1, reason: 'applied together with the answer');
    expect(cubit.state.reactionBurst?.messageId, 5);
    expect(cubit.state.reactionBurst?.emoji, '❤');
  });

  test('failure: the glow ends, nothing changes, no burst', () async {
    final done = cubit.toggleReaction(cubit.state.messages.single, '❤');
    await pumpEventQueue();
    answer.complete(const td.TdError(code: 400, message: 'REACTION_INVALID'));
    await expectLater(done, throwsA(anything));
    expect(cubit.isReactionPending(5, '❤'), isFalse);
    expect(count(), isNull);
    expect(cubit.state.reactionBurst, isNull);
  });
}
