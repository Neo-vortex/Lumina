import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/telegram/telegram_cache.dart';
import '../data/folders_repository.dart';
import '../domain/folder_errors.dart';

class JoinFolderState {
  const JoinFolderState({
    this.title = '',
    this.chatIds = const [],
    this.alreadyIn = const {},
    this.selected = const {},
    this.existing = false,
    this.loading = true,
    this.joining = false,
    this.done = false,
    this.error,
  });

  final String title;
  final List<int> chatIds;
  final Set<int> alreadyIn;
  final Set<int> selected;

  /// We already have this folder (joining more of its chats).
  final bool existing;
  final bool loading;
  final bool joining;
  final bool done;
  final String? error;

  JoinFolderState copyWith({
    String? title,
    List<int>? chatIds,
    Set<int>? alreadyIn,
    Set<int>? selected,
    bool? existing,
    bool? loading,
    bool? joining,
    bool? done,
    String? Function()? error,
  }) => JoinFolderState(
    title: title ?? this.title,
    chatIds: chatIds ?? this.chatIds,
    alreadyIn: alreadyIn ?? this.alreadyIn,
    selected: selected ?? this.selected,
    existing: existing ?? this.existing,
    loading: loading ?? this.loading,
    joining: joining ?? this.joining,
    done: done ?? this.done,
    error: error != null ? error() : this.error,
  );
}

/// Joining a folder from a `t.me/addlist` link, or adding the chats the
/// owner of a joined shared folder added since.
class JoinFolderCubit extends Cubit<JoinFolderState> {
  JoinFolderCubit.link({required this._repository, required String url})
    : _url = url,
      _cache = null,
      _folderId = null,
      _newChatIds = const [],
      super(const JoinFolderState());

  JoinFolderCubit.newChats({
    required this._repository,
    required TelegramCache cache,
    required int folderId,
    required List<int> chatIds,
  }) : _url = null,
       _cache = cache,
       _folderId = folderId,
       _newChatIds = chatIds,
       super(const JoinFolderState());

  final FoldersRepository _repository;
  final String? _url;
  final TelegramCache? _cache;
  final int? _folderId;
  final List<int> _newChatIds;

  Future<void> load() async {
    final url = _url;
    if (url == null) {
      final folder = _cache!.chatFolders.where((f) => f.id == _folderId).firstOrNull;
      emit(
        state.copyWith(
          title: folder?.name.text.text ?? 'Folder',
          chatIds: _newChatIds,
          selected: {..._newChatIds},
          existing: true,
          loading: false,
        ),
      );
      return;
    }
    try {
      final info = await _repository.checkLink(url);
      emit(
        state.copyWith(
          title: info.chatFolderInfo.name.text.text,
          chatIds: [...info.missingChatIds, ...info.addedChatIds],
          alreadyIn: {...info.addedChatIds},
          selected: {...info.missingChatIds},
          existing: info.chatFolderInfo.id != 0,
          loading: false,
        ),
      );
    } catch (e) {
      emit(state.copyWith(loading: false, error: () => folderErrorText(e)));
    }
  }

  void toggle(int chatId) {
    if (state.alreadyIn.contains(chatId)) return;
    final next = {...state.selected};
    next.contains(chatId) ? next.remove(chatId) : next.add(chatId);
    emit(state.copyWith(selected: next));
  }

  Future<void> join() => _send(state.selected.toList());

  /// New chats only: dismiss them.
  Future<void> notNow() => _send(const []);

  Future<void> _send(List<int> chatIds) async {
    emit(state.copyWith(joining: true, error: () => null));
    try {
      final url = _url;
      if (url != null) {
        await _repository.join(url, chatIds);
      } else {
        await _repository.processNewChats(_folderId!, chatIds);
      }
      emit(state.copyWith(joining: false, done: true));
    } catch (e) {
      emit(state.copyWith(joining: false, error: () => folderErrorText(e)));
    }
  }
}
