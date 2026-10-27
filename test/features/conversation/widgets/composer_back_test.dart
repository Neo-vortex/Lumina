import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/conversation/presentation/widgets/composer.dart';

import '../../../helpers/fakes.dart';

void main() {
  testWidgets('back closes the media panel, then the reply, then leaves the chat', (tester) async {
    var replying = true;
    late StateSetter setOuter;
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => TelegramCache(FakeTdClient()),
        child: MaterialApp(home: const Scaffold(body: Text('list'))),
      ),
    );
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: Composer(
                  controller: TextEditingController(),
                  replyTo: replying ? fakeMessage(5) : null,
                  editing: null,
                  onSend: (_, _, _) async {},
                  onCancelMode: () => setOuter(() => replying = false),
                  onChanged: (_) {},
                  mediaPanel: (height, _, _) => SizedBox(key: const ValueKey('panel'), height: height),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Emoji, stickers and GIFs'));
    await tester.pump();
    expect(find.byKey(const ValueKey('panel')), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pump();
    expect(find.byKey(const ValueKey('panel')), findsNothing);
    expect(replying, isTrue, reason: 'one layer per back');
    expect(nav.canPop(), isTrue);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pump();
    expect(replying, isFalse);
    expect(nav.canPop(), isTrue);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('list'), findsOneWidget);
    expect(nav.canPop(), isFalse);
  });
}
