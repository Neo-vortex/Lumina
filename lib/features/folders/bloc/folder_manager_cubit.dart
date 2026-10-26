import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/telegram_cache.dart';
import '../data/folders_repository.dart';
import '../domain/folder_errors.dart';

/// A row on the Edit folders screen; a null [folder] is All chats.
class ManagerRow {
  const ManagerRow(this.folder);
  final td.ChatFolderInfo? folder;
  bool get isMain => folder == null;
}

class FolderManagerState {
  const FolderManagerState({
    this.rows = const [],
    this.tagsEnabled = false,
    this.recommended = const [],
    this.error,
  });

  final List<ManagerRow> rows;
  final bool tagsEnabled;
  final List<td.RecommendedChatFolder> recommended;
  final String? error;

  FolderManagerState copyWith({
    List<ManagerRow>? rows,
    bool? tagsEnabled,
    List<td.RecommendedChatFolder>? recommended,
    String? Function()? error,
  }) => FolderManagerState(
    rows: rows ?? this.rows,
    tagsEnabled: tagsEnabled ?? this.tagsEnabled,
    recommended: recommended ?? this.recommended,
    error: error != null ? error() : this.error,
  );
}

class FolderManagerCubit extends Cubit<FolderManagerState> {
  FolderManagerCubit({required this._repository, required this._cache}) : super(const FolderManagerState()) {
    _sub = _cache.events.where((e) => e is FoldersChanged).listen((_) => _fromCache());
    _fromCache();
  }

  final FoldersRepository _repository;
  final TelegramCache _cache;
  late final StreamSubscription<CacheEvent> _sub;

  bool get isPremium => _repository.isPremium;

  void _fromCache() {
    if (isClosed) return;
    final folders = [for (final f in _cache.chatFolders) ManagerRow(f)];
    final at = _cache.mainListPosition.clamp(0, folders.length);
    emit(
      state.copyWith(
        rows: [...folders.take(at), const ManagerRow(null), ...folders.skip(at)],
        tagsEnabled: _cache.folderTagsEnabled,
      ),
    );
  }

  Future<void> load() async {
    _fromCache();
    try {
      final r = await _repository.recommended();
      if (!isClosed) emit(state.copyWith(recommended: r));
    } on Exception {
      // Suggestions are optional.
    }
  }

  /// [newIndex] as ReorderableListView reports it (before removal).
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    final before = state.rows;
    final rows = [...before];
    rows.insert(newIndex, rows.removeAt(oldIndex));
    final mainAt = rows.indexWhere((r) => r.isMain);
    if (mainAt != 0 && !_repository.isPremium) {
      emit(state.copyWith(error: () => 'Moving All chats needs Telegram Premium'));
      return;
    }
    emit(state.copyWith(rows: rows, error: () => null));
    try {
      await _repository.reorder([
        for (final r in rows)
          if (r.folder != null) r.folder!.id,
      ], mainAt);
    } catch (e) {
      if (!isClosed) emit(state.copyWith(rows: before, error: () => folderErrorText(e)));
    }
  }

  Future<void> delete(int id, {List<int> leave = const []}) =>
      _guard(() => _repository.delete(id, leaveChatIds: leave));

  Future<List<int>> chatsToLeave(int id) => _repository.chatsToLeave(id);

  Future<void> addRecommended(td.RecommendedChatFolder r) => _guard(() async {
    await _repository.addRecommended(r.folder);
    if (!isClosed) emit(state.copyWith(recommended: [...state.recommended]..remove(r)));
  });

  Future<void> setTags(bool on) => _guard(() => _repository.setTagsEnabled(on));

  Future<void> _guard(Future<void> Function() action) async {
    try {
      emit(state.copyWith(error: () => null));
      await action();
    } catch (e) {
      if (!isClosed) emit(state.copyWith(error: () => folderErrorText(e)));
    }
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
