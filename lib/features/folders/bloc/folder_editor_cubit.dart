import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/telegram_cache.dart';
import '../data/folders_repository.dart';
import '../domain/folder_draft.dart';
import '../domain/folder_errors.dart';

class FolderEditorState {
  const FolderEditorState({
    this.draft = const FolderDraft.empty(),
    this.loading = true,
    this.saving = false,
    this.changed = false,
    this.done = false,
    this.deleted = false,
    this.error,
  });

  final FolderDraft draft;
  final bool loading;
  final bool saving;
  final bool changed;
  final bool done;
  final bool deleted;
  final String? error;

  FolderEditorState copyWith({
    FolderDraft? draft,
    bool? loading,
    bool? saving,
    bool? changed,
    bool? done,
    bool? deleted,
    String? Function()? error,
  }) => FolderEditorState(
    draft: draft ?? this.draft,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    changed: changed ?? this.changed,
    done: done ?? this.done,
    deleted: deleted ?? this.deleted,
    error: error != null ? error() : this.error,
  );
}

class FolderEditorCubit extends Cubit<FolderEditorState> {
  FolderEditorCubit({required this._repository, required this._cache, this.folderId, FolderDraft? initial})
    : _initial = initial,
      super(const FolderEditorState());

  final FoldersRepository _repository;
  final TelegramCache _cache;
  final FolderDraft? _initial;

  /// Null for a new folder.
  final int? folderId;

  static const _deletedText = 'This folder was deleted';

  Future<void> load() async {
    final id = folderId;
    if (id == null) {
      emit(state.copyWith(draft: _initial ?? const FolderDraft.empty(), loading: false));
      return;
    }
    try {
      var draft = FolderDraft.fromFolder(await _repository.folder(id));
      if (draft.colorId < 0) draft = draft.copyWith(colorId: _repository.localColor(id) ?? -1);
      emit(state.copyWith(draft: draft, loading: false));
    } catch (e) {
      final text = folderErrorText(e);
      emit(state.copyWith(loading: false, error: () => text, deleted: text == _deletedText));
    }
  }

  void update(FolderDraft Function(FolderDraft draft) change) =>
      emit(state.copyWith(draft: change(state.draft), changed: true, error: () => null));

  Future<bool> save() async {
    final invalid = state.draft.validate();
    if (invalid != null) {
      emit(state.copyWith(error: () => invalid));
      return false;
    }
    emit(state.copyWith(saving: true, error: () => null));
    try {
      final id = folderId;
      if (id == null) {
        await _repository.create(state.draft);
      } else {
        await _repository.edit(id, state.draft);
      }
      emit(state.copyWith(saving: false, done: true));
      return true;
    } catch (e) {
      final text = folderErrorText(e);
      emit(state.copyWith(saving: false, error: () => text, deleted: text == _deletedText));
      return false;
    }
  }

  /// Rules → explicit chats, so the folder can be shared.
  void convertToChatList() {
    final id = folderId;
    final matching = id == null
        ? const <int>[]
        : [for (final c in _cache.chatsIn(td.ChatListFolder(chatFolderId: id))) c.id];
    update((d) => d.asChatList(matching));
  }
}
