import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/core/telegram/widgets/connection_status.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../helpers/fakes.dart';

void main() {
  late FakeTdClient client;

  Future<void> pump(WidgetTester tester) async {
    client = FakeTdClient();
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => TelegramCache(client),
        child: const MaterialApp(
          home: Scaffold(body: ConnectionAwareTitle(title: 'Chats')),
        ),
      ),
    );
  }

  testWidgets('spinner settles into a static icon after 3 s in one state', (tester) async {
    await pump(tester);
    expect(find.text('Connecting…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a new state restarts the spinner', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(seconds: 4));
    client.emitUpdate(const td.UpdateConnectionState(state: td.ConnectionStateUpdating()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Updating…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
