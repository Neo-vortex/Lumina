import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/chats/domain/lens_entry.dart';
import 'package:lumina/features/chats/presentation/widgets/lens_picker.dart';
import 'package:lumina_tdlib/api.dart' as td;

void main() {
  testWidgets('lists every lens with unread pills and returns the picked one', (tester) async {
    const entries = [
      LensEntry(list: td.ChatListMain(), title: 'All chats', unread: (chats: 3, unmuted: 1)),
      LensEntry(list: td.ChatListFolder(chatFolderId: 4), title: 'Work', unread: (chats: 2, unmuted: 0)),
      LensEntry(list: td.ChatListArchive(), title: 'Archive'),
    ];
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showLensPicker(context, entries: entries, current: 0),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(picked, 1);
  });
}
