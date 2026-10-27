import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/tdlib/td_client.dart';
import 'package:lumina/features/conversation/presentation/widgets/inline_keyboard.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../helpers/fakes.dart';

td.InlineKeyboardButton button(String text, td.InlineKeyboardButtonType type) => td.InlineKeyboardButton(
  text: text,
  iconCustomEmojiId: 0,
  style: const td.ButtonStyleDefault(),
  type: type,
);

void main() {
  late FakeTdClient client;
  String? switched;

  Future<void> pump(WidgetTester tester, List<List<td.InlineKeyboardButton>> rows) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    switched = null;
    await tester.pumpWidget(
      RepositoryProvider<TdClient>.value(
        value: client,
        child: MaterialApp(
          home: Scaffold(
            body: InlineKeyboard(
              message: fakeMessage(5, chatId: 3),
              markup: td.ReplyMarkupInlineKeyboard(rows: rows, forceReply: false),
              botUsername: 'helperbot',
              onSwitchInline: (q) => switched = q,
            ),
          ),
        ),
      ),
    );
  }

  setUp(() => client = FakeTdClient());

  testWidgets('renders every row of buttons', (tester) async {
    await pump(tester, [
      [
        button('A', const td.InlineKeyboardButtonTypeCallback(data: 'a')),
        button('B', const td.InlineKeyboardButtonTypeCallback(data: 'b')),
      ],
      [button('C', const td.InlineKeyboardButtonTypeCallback(data: 'c'))],
    ]);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('a callback asks the bot and shows its answer as a toast', (tester) async {
    final answer = Completer<td.TdObject>();
    client.respond = (f) => f is td.GetCallbackQueryAnswer ? answer.future : const td.Ok();
    await pump(tester, [
      [button('Go', const td.InlineKeyboardButtonTypeCallback(data: 'Z28='))],
    ]);
    await tester.tap(find.text('Go'));
    await tester.pump();
    final req = client.sentOf<td.GetCallbackQueryAnswer>().single;
    expect(req.chatId, 3);
    expect(req.messageId, 5);
    expect((req.payload as td.CallbackQueryPayloadData).data, 'Z28=');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    answer.complete(const td.CallbackQueryAnswer(text: 'Done!', showAlert: false, url: ''));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Done!'), findsOneWidget);
  });

  testWidgets('an alert answer opens a glow sheet', (tester) async {
    client.respond = (f) => f is td.GetCallbackQueryAnswer
        ? const td.CallbackQueryAnswer(text: 'Careful', showAlert: true, url: '')
        : const td.Ok();
    await pump(tester, [
      [button('Go', const td.InlineKeyboardButtonTypeCallback(data: 'x'))],
    ]);
    await tester.tap(find.text('Go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Careful'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('copy text puts it on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await pump(tester, [
      [button('Code', const td.InlineKeyboardButtonTypeCopyText(text: 'PROMO42'))],
    ]);
    await tester.tap(find.text('Code'));
    await tester.pump();
    expect(copied, 'PROMO42');
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('switch inline puts "@bot query" in the composer', (tester) async {
    await pump(tester, [
      [
        button(
          'Share',
          const td.InlineKeyboardButtonTypeSwitchInline(query: 'cats', targetChat: td.TargetChatCurrent()),
        ),
      ],
    ]);
    await tester.tap(find.text('Share'));
    await tester.pump();
    expect(switched, '@helperbot cats');
  });

  testWidgets('unsupported buttons say so', (tester) async {
    await pump(tester, [
      [button('Pay', const td.InlineKeyboardButtonTypeBuy())],
    ]);
    await tester.tap(find.text('Pay'));
    await tester.pump();
    expect(find.text('Not supported yet'), findsOneWidget);
    expect(client.sent, isEmpty);
  });
}
