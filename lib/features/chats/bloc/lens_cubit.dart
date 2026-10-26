import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/telegram_cache.dart';
import '../domain/lens_entry.dart';

class LensState {
  const LensState({this.entries = const [], this.index = 0});

  final List<LensEntry> entries;
  final int index;

  LensEntry? get current => index < entries.length ? entries[index] : null;
}

/// The chat lists the lens pages through, in Telegram's order: folders
/// with All chats at `main_chat_list_position`, then Archive.
class LensCubit extends Cubit<LensState> {
  LensCubit({required this._cache, required this._isBot}) : super(const LensState()) {
    _sub = _cache.events.listen((e) {
      if (e is FoldersChanged || e is UnreadCountChanged) _rebuild();
    });
    _rebuild();
  }

  final TelegramCache _cache;
  final bool _isBot;
  late final StreamSubscription<CacheEvent> _sub;

  void select(int index) {
    if (index == state.index || index < 0 || index >= state.entries.length) return;
    emit(LensState(entries: state.entries, index: index));
  }

  void selectList(td.ChatList list) {
    final key = TelegramCache.listKey(list);
    final i = state.entries.indexWhere((e) => e.key == key);
    if (i >= 0) select(i);
  }

  void _rebuild() {
    if (isClosed) return;
    final entries = _build();
    final currentKey = state.current?.key ?? 'main';
    var index = entries.indexWhere((e) => e.key == currentKey);
    if (index < 0) index = entries.indexWhere((e) => e.isMain);
    emit(LensState(entries: entries, index: index));
  }

  List<LensEntry> _build() {
    LensEntry entry(td.ChatList list, String title, [td.ChatFolderInfo? folder]) =>
        LensEntry(list: list, title: title, folder: folder, unread: _cache.unreadIn(list));
    if (_isBot) return [entry(const td.ChatListMain(), 'Chats')];
    final folders = [
      for (final f in _cache.chatFolders) entry(td.ChatListFolder(chatFolderId: f.id), f.name.text.text, f),
    ];
    final at = _cache.mainListPosition.clamp(0, folders.length);
    return [
      ...folders.take(at),
      entry(const td.ChatListMain(), 'All chats'),
      ...folders.skip(at),
      entry(const td.ChatListArchive(), 'Archive'),
    ];
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
