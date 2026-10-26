import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/gestures/swipe_actions.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/conversation/presentation/widgets/message_bubble.dart';
import 'package:lumina/features/conversation/presentation/widgets/message_rows.dart';

import '../../../helpers/fakes.dart';

void main() {
  Future<List<SwipeSide>> pump(
    WidgetTester tester, {
    required MessageSwipe left,
    required MessageSwipe right,
  }) async {
    final swiped = <SwipeSide>[];
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => TelegramCache(FakeTdClient()),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: MessageBubble(
                row: BubbleRow(messages: [fakeMessage(1)], firstInRun: true, lastInRun: true),
                chat: fakeChat(1),
                isGroup: false,
                isChannel: false,
                animateIn: false,
                highlighted: false,
                selected: false,
                selecting: false,
                swipeLeft: left,
                swipeRight: right,
                swipeEmoji: '❤️',
                onSwipe: swiped.add,
                onLongPress: () {},
                onTap: () {},
                onReplyQuoteTap: (_) {},
                onReaction: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    return swiped;
  }

  testWidgets('each direction fires its own configured action', (tester) async {
    final swiped = await pump(tester, left: MessageSwipe.reply, right: MessageSwipe.delete);
    await tester.drag(find.text('hi'), const Offset(160, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.drag(find.text('hi'), const Offset(-160, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(swiped, [SwipeSide.right, SwipeSide.left]);
  });

  testWidgets('a side set to Nothing does not swipe', (tester) async {
    final swiped = await pump(tester, left: MessageSwipe.none, right: MessageSwipe.react);
    await tester.drag(find.text('hi'), const Offset(-160, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(swiped, isEmpty);
  });
}
