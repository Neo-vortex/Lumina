import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/core/telegram/widgets/connection_status.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../helpers/fakes.dart';

void main() {
  late FakeTdClient client;

  Future<List<String>> pump(WidgetTester tester) async {
    client = FakeTdClient();
    final taps = <String>[];
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => TelegramCache(client),
        child: MaterialApp(
          home: Scaffold(
            body: ConnectionAwareTitle(title: 'Chats', onStatusTap: () => taps.add('status')),
          ),
        ),
      ),
    );
    return taps;
  }

  testWidgets('the folder title stays; a status capsule sits beside it and opens connection settings', (
    tester,
  ) async {
    final taps = await pump(tester);
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Connecting'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'no Telegram-style spinner');
    await tester.tap(find.text('Connecting'));
    expect(taps, ['status']);
  });

  testWidgets('the capsule pulses briefly, then rests: no frames at idle', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(seconds: 4));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('each state has its own word; ready hides the capsule', (tester) async {
    await pump(tester);
    client.emitUpdate(const td.UpdateConnectionState(state: td.ConnectionStateWaitingForNetwork()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No network'), findsOneWidget);
    client.emitUpdate(const td.UpdateConnectionState(state: td.ConnectionStateReady()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No network'), findsNothing);
    expect(find.text('Chats'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
