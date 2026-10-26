import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/chats/bloc/lens_cubit.dart';
import 'package:lumina_tdlib/api.dart' as td;

td.ChatFolderInfo info(int id, String name) => td.ChatFolderInfo(
  id: id,
  name: td.ChatFolderName(
    text: td.FormattedText(text: name, entities: const []),
    animateCustomEmoji: false,
  ),
  icon: const td.ChatFolderIcon(name: 'Custom'),
  colorId: -1,
  isShareable: false,
  hasMyInviteLinks: false,
);

void main() {
  late TelegramCache cache;
  setUp(() => cache = TelegramCache.detached());

  void folders(List<td.ChatFolderInfo> f, {int main = 0}) =>
      cache.apply(td.UpdateChatFolders(chatFolders: f, mainChatListPosition: main, areTagsEnabled: false));

  List<String> titles(LensCubit c) => c.state.entries.map((e) => e.title).toList();

  test('All chats, then folders, then Archive', () async {
    folders([info(3, 'Work'), info(5, 'Home')]);
    final c = LensCubit(cache: cache, isBot: false);
    expect(titles(c), ['All chats', 'Work', 'Home', 'Archive']);
    expect(c.state.current!.isMain, isTrue);
    await c.close();
  });

  test('places All chats at main_chat_list_position', () async {
    folders([info(3, 'Work'), info(5, 'Home')], main: 1);
    final c = LensCubit(cache: cache, isBot: false);
    expect(titles(c), ['Work', 'All chats', 'Home', 'Archive']);
    expect(c.state.current!.isMain, isTrue, reason: 'opens on All chats wherever it is');
    await c.close();
  });

  test('follows folder updates and keeps the current lens', () async {
    final c = LensCubit(cache: cache, isBot: false);
    expect(titles(c), ['All chats', 'Archive']);
    folders([info(3, 'Work')]);
    c.selectList(const td.ChatListFolder(chatFolderId: 3));
    folders([info(9, 'New'), info(3, 'Work')]);
    expect(c.state.current!.folderId, 3);
    await c.close();
  });

  test('falls back to All chats when the current folder disappears', () async {
    folders([info(3, 'Work'), info(5, 'Home')], main: 1);
    final c = LensCubit(cache: cache, isBot: false);
    c.selectList(const td.ChatListFolder(chatFolderId: 5));
    folders([info(3, 'Work')], main: 1);
    expect(c.state.current!.isMain, isTrue);
    await c.close();
  });

  test('carries unread counts', () async {
    folders([info(3, 'Work')]);
    final c = LensCubit(cache: cache, isBot: false);
    cache.apply(
      const td.UpdateUnreadChatCount(
        chatList: td.ChatListFolder(chatFolderId: 3),
        totalCount: 5,
        unreadCount: 2,
        unreadUnmutedCount: 1,
        markedAsUnreadCount: 0,
        markedAsUnreadUnmutedCount: 0,
      ),
    );
    expect(c.state.entries[1].unread, (chats: 2, unmuted: 1));
    await c.close();
  });

  test('bots get only the main list', () async {
    folders([info(3, 'Work')]);
    final c = LensCubit(cache: cache, isBot: true);
    expect(titles(c), ['Chats']);
    await c.close();
  });
}
