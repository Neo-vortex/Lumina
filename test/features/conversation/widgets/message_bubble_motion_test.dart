import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/conversation/presentation/widgets/message_bubble.dart';
import 'package:lumina/features/conversation/presentation/widgets/message_rows.dart';

import '../../../helpers/fakes.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool animateIn, bool disableAnimations = false}) async {
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => TelegramCache(FakeTdClient()),
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: Scaffold(
              body: MessageBubble(
                row: BubbleRow(messages: [fakeMessage(1)], firstInRun: true, lastInRun: true),
                chat: fakeChat(1),
                isGroup: false,
                isChannel: false,
                animateIn: animateIn,
                highlighted: false,
                selected: false,
                selecting: false,
                onSwipe: (_) {},
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
  }

  testWidgets('with animations disabled a new bubble appears at once, no entrance slide', (tester) async {
    await pump(tester, animateIn: true, disableAnimations: true);
    expect(
      find.descendant(of: find.byType(MessageBubble), matching: find.byType(SlideTransition)),
      findsNothing,
    );
  });

  testWidgets('a bubble that does not animate in carries no fade or slide wrappers', (tester) async {
    await pump(tester, animateIn: false);
    expect(
      find.descendant(of: find.byType(MessageBubble), matching: find.byType(SlideTransition)),
      findsNothing,
    );
  });
}
