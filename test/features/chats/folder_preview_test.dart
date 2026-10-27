import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/chats/presentation/widgets/folder_preview.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

void main() {
  test('unread chats come first, then the rest, capped', () {
    final cache = TelegramCache.detached();
    for (var i = 1; i <= 8; i++) {
      cache.apply(
        td.UpdateNewChat(
          chat: fakeChat(i, order: 100 - i, unread: i.isEven ? i : 0),
        ),
      );
    }
    final p = FolderPreview.of(cache, const td.ChatListMain());
    expect(p.chats.map((c) => c.id), [2, 4, 6, 8, 1, 3]);
    expect(p.unreadChats, 4);
    expect(p.unreadMessages, 2 + 4 + 6 + 8);
    expect(p.headline, '20 unread in 4 chats');
  });

  test('an empty or fully read folder says so', () {
    final cache = TelegramCache.detached()..apply(td.UpdateNewChat(chat: fakeChat(1, order: 5)));
    expect(FolderPreview.of(cache, const td.ChatListMain()).headline, 'No unread chats');
    expect(FolderPreview.of(cache, const td.ChatListArchive()).chats, isEmpty);
  });

  test('one unread chat is singular', () {
    final cache = TelegramCache.detached()..apply(td.UpdateNewChat(chat: fakeChat(1, order: 5, unread: 3)));
    expect(FolderPreview.of(cache, const td.ChatListMain()).headline, '3 unread in 1 chat');
  });
}
