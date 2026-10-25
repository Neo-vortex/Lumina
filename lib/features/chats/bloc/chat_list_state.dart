part of 'chat_list_cubit.dart';

class ChatListState {
  const ChatListState({
    this.chats = const [],
    this.loading = true,
    this.allLoaded = false,
    this.error,
    this.revision = 0,
  });

  final List<td.Chat> chats;
  final bool loading;
  final bool allLoaded;
  final String? error;

  /// Bumped on any visible change (typing, unread, user status) so rows
  /// re-read the cache even when the list order is unchanged.
  final int revision;

  ChatListState copyWith({
    List<td.Chat>? chats,
    bool? loading,
    bool? allLoaded,
    String? Function()? error,
    int? revision,
  }) => ChatListState(
    chats: chats ?? this.chats,
    loading: loading ?? this.loading,
    allLoaded: allLoaded ?? this.allLoaded,
    error: error != null ? error() : this.error,
    revision: revision ?? this.revision,
  );
}
