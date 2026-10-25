import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib_next/api.dart' as td;
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/conversation/bloc/conversation_cubit.dart';
import 'package:lumina/features/conversation/data/messages_repository.dart';
import 'package:lumina/features/conversation/presentation/widgets/message_menu.dart';

import '../../helpers/fakes.dart';

void main() {
  group('quoteFromSelection', () {
    const message = td.FormattedText(
      text: 'Meet at the old bridge at noon',
      entities: [
        td.TextEntity(offset: 12, length: 10, type: td.TextEntityTypeBold()), // "old bridge"
        td.TextEntity(offset: 0, length: 4, type: td.TextEntityTypeItalic()), // "Meet"
        td.TextEntity(offset: 26, length: 4, type: td.TextEntityTypeCode()), // "noon"
      ],
    );

    test('finds the passage and its position', () {
      final q = quoteFromSelection(message, '  the old bridge ')!;
      expect(q.text.text, 'the old bridge');
      expect(q.position, 8);
    });

    test('keeps allowed entities clipped to the passage, drops others', () {
      final q = quoteFromSelection(message, 'old bridge at noon')!;
      expect(q.text.entities, hasLength(1));
      final bold = q.text.entities.single;
      expect((bold.offset, bold.length), (0, 10));
      expect(bold.type, isA<td.TextEntityTypeBold>());

      final partial = quoteFromSelection(message, 'bridge')!;
      expect((partial.text.entities.single.offset, partial.text.entities.single.length), (0, 6));
    });

    test('nothing to quote', () {
      expect(quoteFromSelection(message, '   '), isNull);
      expect(quoteFromSelection(message, 'not in there'), isNull);
    });

    test('clips to the maximum quote length', () {
      final q = quoteFromSelection(message, 'Meet at the old bridge', maxLength: 7)!;
      expect(q.text.text, 'Meet at');
      expect(q.text.entities.single.length, 4);
    });
  });

  test('a new reply target drops the quote unless one is given', () {
    const quote = td.InputTextQuote(
      text: td.FormattedText(text: 'x', entities: []),
      position: 0,
    );
    final m = fakeMessage(1), other = fakeMessage(2);
    final quoted = const ConversationState(chatId: 1).copyWith(replyTo: () => m, replyQuote: () => quote);
    expect(quoted.replyQuote, quote);
    expect(quoted.copyWith(revision: 3).replyQuote, quote);
    expect(quoted.copyWith(replyTo: () => other).replyQuote, isNull);
    expect(quoted.copyWith(replyTo: () => null).replyQuote, isNull);
  });

  test('the quote goes out with the reply and into drafts', () async {
    final client = FakeTdClient()..respond = (_) => fakeMessage(9);
    final repo = MessagesRepository(client: client, prefs: AppPreferences.inMemory());
    const quote = td.InputTextQuote(
      text: td.FormattedText(text: 'bridge', entities: []),
      position: 16,
    );
    await repo.sendText(1, 'on my way', replyToMessageId: 5, quote: quote);
    final reply = client.sentOf<td.SendMessage>().single.replyTo as td.InputMessageReplyToMessage;
    expect(reply.messageId, 5);
    expect(reply.quote?.position, 16);

    client.respond = (_) => const td.Ok();
    await repo.saveDraft(1, 'on my', replyToMessageId: 5, quote: quote);
    final draft = client.sentOf<td.SetChatDraftMessage>().single.draftMessage!;
    expect((draft.replyTo as td.InputMessageReplyToMessage).quote?.text.text, 'bridge');
  });
}
