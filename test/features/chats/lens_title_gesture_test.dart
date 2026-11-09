import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/chats/domain/lens_entry.dart';
import 'package:lumina/features/chats/presentation/widgets/lens_title.dart';
import 'package:lumina_tdlib/api.dart' as td;

Widget host(Widget child) => RepositoryProvider.value(
  value: TelegramCache.detached(),
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  const entry = LensEntry(list: td.ChatListMain(), title: 'All chats');

  testWidgets('holding the title streams the gesture; a tap still taps', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(
      host(
        LensTitle(
          entry: entry,
          color: Colors.purple,
          onTap: () => events.add('tap'),
          onHoldStart: (_) => events.add('start'),
          onHoldMove: (_) => events.add('move'),
          onHoldEnd: (_) => events.add('end'),
        ),
      ),
    );
    await tester.tap(find.byType(LensTitle));
    await tester.pump(const Duration(milliseconds: 400));
    expect(events, ['tap']);

    final g = await tester.startGesture(tester.getCenter(find.byType(LensTitle)));
    await tester.pump(const Duration(milliseconds: 300));
    await g.moveBy(const Offset(0, 120));
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(events, ['tap', 'start', 'move', 'end']);
  });

  testWidgets('without hold callbacks a slow press is still a tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(LensTitle(entry: entry, color: Colors.purple, onTap: () => taps++)));
    final g = await tester.startGesture(tester.getCenter(find.byType(LensTitle)));
    await tester.pump(const Duration(milliseconds: 600));
    await g.up();
    expect(taps, 1, reason: 'tap-only titles keep today’s behaviour: a slow press still opens the list');
  });

  testWidgets('if holding is switched off mid-hold, the hold is cancelled', (tester) async {
    final events = <String>[];
    Widget title({required bool hold}) => host(
      LensTitle(
        entry: entry,
        color: Colors.purple,
        onTap: () {},
        onHoldStart: hold ? (_) => events.add('start') : null,
        onHoldMove: (_) => events.add('move'),
        onHoldEnd: (_) => events.add('end'),
        onHoldCancel: () => events.add('cancel'),
      ),
    );
    await tester.pumpWidget(title(hold: true));
    final g = await tester.startGesture(tester.getCenter(find.byType(LensTitle)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(events, ['start']);
    await tester.pumpWidget(title(hold: false)); // e.g. folders dropped to one
    expect(events, ['start', 'cancel']);
    await g.up();
  });
}
