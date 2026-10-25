import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/tdlib/td_errors.dart';
import '../../../core/telegram/telegram_cache.dart';
import '../data/chats_repository.dart';

part 'chat_list_state.dart';

/// The main chat list, projected from [TelegramCache] and paged with
/// `loadChats`. Cache bursts are coalesced into one emit per frame-ish
/// window so a sync of hundreds of updates does not rebuild hundreds of times.
class ChatListCubit extends Cubit<ChatListState> {
  ChatListCubit({required this._repository, this._list = const td.ChatListMain()})
    : super(const ChatListState()) {
    _subscription = _repository.cache.events.listen(_onCacheEvent);
  }

  final ChatsRepository _repository;
  final td.ChatList _list;
  StreamSubscription<CacheEvent>? _subscription;
  Timer? _coalesce;
  var _loadingMore = false;

  Future<void> start() async {
    _rebuild();
    await loadMore();
  }

  Future<void> loadMore() async {
    if (_loadingMore || state.allLoaded) return;
    _loadingMore = true;
    emit(state.copyWith(loading: true, error: () => null));
    try {
      final more = await _repository.loadMore(list: _list);
      if (!isClosed) emit(state.copyWith(loading: false, allLoaded: !more));
    } on TdException catch (e) {
      // Bots cannot list chats; their list fills from incoming updates.
      if (!isClosed) {
        emit(state.copyWith(loading: false, allLoaded: true, error: () => e.code == 400 ? null : e.message));
      }
    } finally {
      _loadingMore = false;
    }
  }

  /// Pull-to-refresh: re-request the first page.
  Future<void> refresh() async {
    emit(state.copyWith(allLoaded: false));
    await loadMore();
  }

  void _onCacheEvent(CacheEvent event) {
    final relevant = switch (event) {
      ChatChanged() || TypingChanged() || UserChanged() || SecretChatChanged() => true,
      _ => false,
    };
    if (!relevant) return;
    _coalesce ??= Timer(const Duration(milliseconds: 80), () {
      _coalesce = null;
      _rebuild();
    });
  }

  void _rebuild() {
    if (isClosed) return;
    emit(state.copyWith(chats: _repository.cache.chatsIn(_list), revision: state.revision + 1));
  }

  @override
  Future<void> close() async {
    _coalesce?.cancel();
    await _subscription?.cancel();
    return super.close();
  }
}
