import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/conversation/presentation/widgets/composer.dart';

import '../../../helpers/fakes.dart';

void main() {
  testWidgets('the writing-help button shows once there is text, and opens the tools', (tester) async {
    final text = TextEditingController();
    var opened = 0;
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => TelegramCache(FakeTdClient()),
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Composer(
                controller: text,
                replyTo: null,
                editing: null,
                onSend: (_, _, _) async {},
                onCancelMode: () {},
                onChanged: (_) {},
                onWritingTools: () => opened++,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip('Writing help'), findsNothing);
    await tester.enterText(find.byType(TextField), 'i will came at 8');
    await tester.pump();
    await tester.tap(find.byTooltip('Writing help'));
    expect(opened, 1);
    await tester.pump(const Duration(seconds: 2));
  });
}
