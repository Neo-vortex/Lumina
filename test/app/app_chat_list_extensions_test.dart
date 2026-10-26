import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/app/app_chat_list_extensions.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/core/theme/glow_colors.dart';
import 'package:lumina/features/chats/domain/lens_entry.dart';
import 'package:lumina/features/folders/data/folders_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../features/folders/folders_repository_test.dart' show info;
import '../helpers/fakes.dart';

void main() {
  test('lens colours: Telegram colour, local colour, position, archive', () {
    final cache = TelegramCache.detached()
      ..apply(
        td.UpdateChatFolders(
          chatFolders: [info(1, colorId: 0), info(2), info(3)],
          mainChatListPosition: 0,
          areTagsEnabled: false,
        ),
      );
    final prefs = AppPreferences.inMemory()..folderColorsJson = '{"2": 1}';
    final ext = AppChatListExtensions(
      folders: FoldersRepository(client: FakeTdClient(), cache: cache, prefs: prefs),
      cache: cache,
    );
    LensEntry folder(int i) => LensEntry(
      list: td.ChatListFolder(chatFolderId: cache.chatFolders[i].id),
      title: '',
      folder: cache.chatFolders[i],
    );
    expect(ext.lensColor(folder(0)), GlowColors.coral);
    expect(ext.lensColor(folder(1)), GlowColors.amber);
    expect(ext.lensColor(folder(2)), GlowColors.violet); // position 2 → third palette colour
    expect(ext.lensColor(const LensEntry(list: td.ChatListArchive(), title: '')), GlowColors.archive);
  });
}
