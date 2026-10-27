import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/core/theme/glow_colors.dart';
import 'package:lumina/features/chats/domain/lens_entry.dart';
import 'package:lumina/features/chats/presentation/widgets/folder_gesture_picker.dart';
import 'package:lumina/features/chats/presentation/widgets/folder_picker_layout.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

void main() {
  const entries = [
    LensEntry(list: td.ChatListMain(), title: 'All chats'),
    LensEntry(list: td.ChatListFolder(chatFolderId: 1), title: 'Work'),
    LensEntry(list: td.ChatListFolder(chatFolderId: 2), title: 'Family'),
    LensEntry(list: td.ChatListArchive(), title: 'Archive'),
  ];
  late BuildContext ctx;
  int? picked;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    picked = null;
    final cache = TelegramCache.detached()
      ..apply(td.UpdateNewChat(chat: fakeChat(5, title: 'Ada', order: 9, unread: 2)))
      ..apply(td.UpdateNewChat(chat: fakeChat(6, title: 'Bob', order: 8)));
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: cache,
        child: MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
  }

  FolderGesturePicker open(Offset start, {List<LensEntry> list = entries, int current = 0}) =>
      FolderGesturePicker.open(
        ctx,
        entries: list,
        current: current,
        colorOf: (_) => GlowColors.violet,
        start: start,
        onPicked: (i) => picked = i,
      );

  // Screen is 360x800 logical; press on the right half → list on the right.
  FolderPickerLayout layoutFor(WidgetTester tester) => FolderPickerLayout(
    screen: const Size(360, 800),
    padding: MediaQuery.of(ctx).padding,
    count: entries.length,
    rightEdge: true,
  );

  testWidgets('sliding to a folder and releasing switches to it', (tester) async {
    await pump(tester);
    final picker = open(const Offset(300, 100));
    await tester.pump();
    expect(find.text('Family'), findsOneWidget);
    final l = layoutFor(tester);
    picker.move(Offset(l.listX, l.centerOf(2)));
    await tester.pump(const Duration(milliseconds: 300));
    picker.end();
    await tester.pump(const Duration(milliseconds: 300));
    expect(picked, 2);
    expect(picker.isOpen, isFalse);
    expect(find.text('Family'), findsNothing);
  });

  testWidgets('the preview shows unread first for the highlighted folder', (tester) async {
    await pump(tester);
    final picker = open(const Offset(300, 100));
    final l = layoutFor(tester);
    picker.move(Offset(l.listX, l.centerOf(0)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('2 unread in 1 chat'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Ada')).dy, lessThan(tester.getTopLeft(find.text('Bob')).dy));
    picker.cancel();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('releasing far from the list cancels', (tester) async {
    await pump(tester);
    final picker = open(const Offset(300, 100));
    final l = layoutFor(tester);
    picker.move(Offset(l.listX - 0.45 * 360, l.centerOf(2)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Release to cancel'), findsOneWidget);
    picker.end();
    await tester.pump(const Duration(milliseconds: 300));
    expect(picked, isNull);
  });

  testWidgets('a system cancel switches nothing', (tester) async {
    await pump(tester);
    final picker = open(const Offset(300, 100));
    final l = layoutFor(tester);
    picker.move(Offset(l.listX, l.centerOf(3)));
    await tester.pump(const Duration(milliseconds: 300));
    picker.cancel();
    await tester.pump(const Duration(milliseconds: 300));
    expect(picked, isNull);
    expect(picker.isOpen, isFalse);
  });

  testWidgets('releasing on the current folder does not switch', (tester) async {
    await pump(tester);
    final picker = open(const Offset(300, 100));
    final l = layoutFor(tester);
    picker.move(Offset(l.listX, l.centerOf(0)));
    await tester.pump(const Duration(milliseconds: 300));
    picker.end();
    await tester.pump(const Duration(milliseconds: 300));
    expect(picked, isNull);
  });
  testWidgets('a rebuild of the host mid-gesture keeps the picker working', (tester) async {
    await pump(tester);
    final picker = open(const Offset(300, 100));
    final l = layoutFor(tester);
    picker.move(Offset(l.listX, l.centerOf(1)));
    await tester.pump(const Duration(milliseconds: 100));
    // Same tree, new widget instance: forces a rebuild of the host.
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: TelegramCache.detached(),
        child: MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    picker.end();
    await tester.pump(const Duration(milliseconds: 300));
    expect(picked, 1);
  });

  testWidgets('holding and releasing without moving keeps the current folder', (tester) async {
    await pump(tester);
    final picker = open(const Offset(40, 20), current: 2);
    await tester.pump(const Duration(milliseconds: 300));
    picker.end();
    await tester.pump(const Duration(milliseconds: 300));
    expect(picked, isNull);
  });

  testWidgets('a long list does not scroll away before the finger moves', (tester) async {
    await pump(tester);
    final many = [
      for (var i = 0; i < 30; i++)
        LensEntry(
          list: td.ChatListFolder(chatFolderId: i + 1),
          title: 'F$i',
        ),
    ];
    final picker = open(const Offset(40, 20), list: many, current: 20);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('F20'), findsOneWidget);
    final y = tester.getCenter(find.text('F20')).dy;
    expect(y, inInclusiveRange(200, 600), reason: 'the current folder stays in view, mid-screen');
    picker.end();
    await tester.pump(const Duration(milliseconds: 300));
    expect(picked, isNull);
  });

  testWidgets('the background is blurred from the first frame, not faded in', (tester) async {
    await pump(tester);
    final picker = open(const Offset(300, 100));
    await tester.pump();
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(
      find.ancestor(of: find.byType(BackdropFilter), matching: find.byType(FadeTransition)),
      findsNothing,
      reason: 'a fading blur looks like the blur arriving late',
    );
    picker.cancel();
    await tester.pump(const Duration(milliseconds: 300));
  });
}
