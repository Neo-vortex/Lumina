import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/telegram_cache.dart';
import '../data/folders_repository.dart';
import '../domain/folder_draft.dart';
import '../domain/folder_errors.dart';

class FolderLinksState {
  const FolderLinksState({
    this.links = const [],
    this.shareable = const [],
    this.loading = true,
    this.needsConversion = false,
    this.error,
  });

  final List<td.ChatFolderInviteLink> links;
  final List<int> shareable;
  final bool loading;

  /// The folder has rules or exclusions; Telegram shares only chat lists.
  final bool needsConversion;
  final String? error;

  FolderLinksState copyWith({
    List<td.ChatFolderInviteLink>? links,
    List<int>? shareable,
    bool? loading,
    bool? needsConversion,
    String? Function()? error,
  }) => FolderLinksState(
    links: links ?? this.links,
    shareable: shareable ?? this.shareable,
    loading: loading ?? this.loading,
    needsConversion: needsConversion ?? this.needsConversion,
    error: error != null ? error() : this.error,
  );
}

class FolderLinksCubit extends Cubit<FolderLinksState> {
  FolderLinksCubit({required this._repository, required this._cache, required this.folderId})
    : super(const FolderLinksState());

  final FoldersRepository _repository;
  final TelegramCache _cache;
  final int folderId;

  Future<void> load() => _guard(() async {
    final draft = FolderDraft.fromFolder(await _repository.folder(folderId));
    if (!draft.canShare) {
      emit(state.copyWith(loading: false, needsConversion: true));
      return;
    }
    final links = await _repository.inviteLinks(folderId);
    final shareable = await _repository.shareableChats(folderId);
    emit(state.copyWith(loading: false, needsConversion: false, links: links, shareable: shareable));
  });

  /// Rules → explicit chats, then load the links.
  Future<void> convert() => _guard(() async {
    final draft = FolderDraft.fromFolder(await _repository.folder(folderId));
    final matching = [for (final c in _cache.chatsIn(td.ChatListFolder(chatFolderId: folderId))) c.id];
    await _repository.edit(folderId, draft.asChatList(matching));
    await load();
  });

  Future<td.ChatFolderInviteLink?> create(String name, List<int> chatIds) async {
    td.ChatFolderInviteLink? created;
    await _guard(() async {
      created = await _repository.createLink(folderId, name: name, chatIds: chatIds);
      emit(state.copyWith(links: [...state.links, created!]));
    });
    return created;
  }

  Future<void> edit(td.ChatFolderInviteLink link, String name, List<int> chatIds) => _guard(() async {
    final updated = await _repository.editLink(folderId, link.inviteLink, name: name, chatIds: chatIds);
    emit(state.copyWith(links: [for (final l in state.links) l.inviteLink == link.inviteLink ? updated : l]));
  });

  Future<void> delete(td.ChatFolderInviteLink link) => _guard(() async {
    await _repository.deleteLink(folderId, link.inviteLink);
    emit(state.copyWith(links: state.links.where((l) => l.inviteLink != link.inviteLink).toList()));
  });

  Future<void> _guard(Future<void> Function() action) async {
    try {
      emit(state.copyWith(error: () => null));
      await action();
    } catch (e) {
      if (!isClosed) emit(state.copyWith(loading: false, error: () => folderErrorText(e)));
    }
  }
}
