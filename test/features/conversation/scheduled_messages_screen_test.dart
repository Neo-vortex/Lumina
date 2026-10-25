import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/conversation/data/messages_repository.dart';
import 'package:lumina/features/conversation/presentation/screens/scheduled_messages_screen.dart';

import '../../helpers/fakes.dart';

void main() {
  final at = DateTime(2026, 11, 2, 9, 30);
  td.Message scheduled(int id, String text, td.MessageSchedulingState state) =>
      fakeMessage(id, outgoing: true, text: text).copyWith(schedulingState: state);

  late FakeTdClient client;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider(create: (_) => TelegramCache(client)),
          RepositoryProvider(
            create: (_) => MessagesRepository(client: client, prefs: AppPreferences.inMemory()),
          ),
        ],
        child: MaterialApp(
          home: ScheduledMessagesScreen(chat: fakeChat(1, title: 'Ana')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetChatScheduledMessages() => td.Messages(
          totalCount: 2,
          messages: [
            scheduled(
              11,
              'see you monday',
              td.MessageSchedulingStateSendAtDate(
                sendDate: at.millisecondsSinceEpoch ~/ 1000,
                repeatPeriod: 0,
              ),
            ),
            scheduled(10, 'ping when online', const td.MessageSchedulingStateSendWhenOnline()),
          ],
        ),
        _ => const td.Ok(),
      };
  });

  testWidgets('lists "when online" first, then by date', (tester) async {
    await pump(tester);
    expect(find.text('WHEN ONLINE'), findsOneWidget);
    expect(find.text('09:30'), findsOneWidget);
    final online = tester.getTopLeft(find.textContaining('ping when online')).dy;
    final monday = tester.getTopLeft(find.textContaining('see you monday')).dy;
    expect(online, lessThan(monday));
  });

  testWidgets('send now clears the scheduling state', (tester) async {
    await pump(tester);
    await tester.tap(find.textContaining('see you monday'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send now'));
    await tester.pumpAndSettle();
    final edit = client.sentOf<td.EditMessageSchedulingState>().single;
    expect(edit.messageId, 11);
    expect(edit.schedulingState, isNull);
    expect(find.text('Sent'), findsOneWidget);
  });

  testWidgets('delete removes it for everyone', (tester) async {
    await pump(tester);
    await tester.tap(find.textContaining('ping when online'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    final delete = client.sentOf<td.DeleteMessages>().single;
    expect(delete.messageIds, [10]);
    expect(delete.revoke, isTrue);
  });

  testWidgets('empty state explains how to schedule', (tester) async {
    client.respond = (f) => const td.Messages(totalCount: 0, messages: []);
    await pump(tester);
    expect(find.textContaining('Long-press the send button'), findsOneWidget);
  });
}
