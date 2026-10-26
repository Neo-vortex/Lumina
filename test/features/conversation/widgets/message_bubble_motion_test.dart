import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/conversation/presentation/widgets/message_bubble.dart';
import 'package:lumina/features/conversation/presentation/widgets/message_rows.dart';

import '../../../helpers/fakes.dart';

void main() {
  testWidgets('with animations disabled a new bubble appears at once, no entrance slide', (tester) async {
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => TelegramCache(FakeTdClient()),
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: MessageBubble(
                row: BubbleRow(messages: [fakeMessage(1)], firstInRun: true, lastInRun: true),
                chat: fakeChat(1),
                isGroup: false,
                isChannel: false,
                animateIn: true,
                highlighted: false,
                selected: false,
                selecting: false,
                onReply: () {},
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
    final fade = tester.widget<FadeTransition>(
      find.descendant(of: find.byType(MessageBubble), matching: find.byType(FadeTransition)).first,
    );
    expect(fade.opacity.value, 1);
  });
}
