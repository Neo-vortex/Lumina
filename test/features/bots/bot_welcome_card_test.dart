import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/tdlib/td_client.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/features/bots/data/bot_start_links.dart';
import 'package:lumina/features/bots/data/bots_repository.dart';
import 'package:lumina/features/bots/presentation/bot_welcome_card.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'bots_repository_test.dart' show bot, fullWithBot;

void main() {
  late FakeTdClient client;
  late BotStartLinks links;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    links = BotStartLinks(client);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<TdClient>.value(value: client),
          RepositoryProvider(create: (_) => FileStore(client)),
          RepositoryProvider(create: (_) => BotsRepository(client)),
          RepositoryProvider.value(value: links),
        ],
        child: const MaterialApp(
          home: Scaffold(body: BotWelcomeCard(botUserId: 9, chatId: 9, title: 'Weather Bot')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    // The card grows (AnimatedSize) once the info arrives.
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('shows the description and Start sends /start once', (tester) async {
    final sent = Completer<td.TdObject>();
    client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetUserFullInfo() => fullWithBot(bot),
        td.SendBotStartMessage() => sent.future,
        _ => const td.Ok(),
      };
    await pump(tester);
    expect(find.text('Weather Bot'), findsOneWidget);
    expect(find.text('I tell you the weather.'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(client.sentOf<td.SendBotStartMessage>(), hasLength(1));
    sent.complete(fakeMessage(1));
    await tester.pump();
  });

  testWidgets('a pending start link parameter goes with Start', (tester) async {
    client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetUserFullInfo() => fullWithBot(bot),
        td.SearchPublicChat() => fakeChat(9),
        td.GetUser() => fakeUser(bot: true).copyWith(id: 9),
        td.SendBotStartMessage() => fakeMessage(1),
        _ => const td.Ok(),
      };
    await pump(tester);
    await links.resolve(Uri.parse('https://t.me/WeatherBot?start=ref42'));
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(client.sentOf<td.SendBotStartMessage>().single.parameter, 'ref42');
  });

  testWidgets('without bot info the card still offers Start', (tester) async {
    client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetUserFullInfo() => const td.TdError(code: 500, message: 'down'),
        td.SendBotStartMessage() => fakeMessage(1),
        _ => const td.Ok(),
      };
    await pump(tester);
    expect(find.text('Weather Bot'), findsOneWidget);
    expect(find.text('I tell you the weather.'), findsNothing);
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(client.sentOf<td.SendBotStartMessage>().single.parameter, '');
  });
}
