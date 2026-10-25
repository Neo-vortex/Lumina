part of 'conversation_cubit.dart';

class ConversationState {
  const ConversationState({
    required this.chatId,
    this.chat,
    this.messages = const [],
    this.initialLoading = true,
    this.loadingOlder = false,
    this.loadingNewer = false,
    this.hasOlder = true,
    this.hasNewer = false,
    this.firstUnreadId,
    this.anchor,
    this.highlightId,
    this.replyTo,
    this.editing,
    this.pinned,
    this.selected = const {},
    this.error,
    this.revision = 0,
  });

  final int chatId;
  final td.Chat? chat;

  /// Loaded window, newest first (index 0 is the bottom of the screen).
  final List<td.Message> messages;

  final bool initialLoading;
  final bool loadingOlder;
  final bool loadingNewer;
  final bool hasOlder;

  /// The window does not reach the latest message (opened at first unread
  /// or jumped to a search result).
  final bool hasNewer;

  /// Where the "Unread messages" divider goes (UX-25).
  final int? firstUnreadId;

  /// One-shot scroll request for the UI: (messageId, request serial).
  final ({int messageId, int serial})? anchor;

  /// Briefly glows after a jump (reply tap, search result, pinned banner).
  final int? highlightId;

  final td.Message? replyTo;
  final td.Message? editing;
  final td.Message? pinned;

  /// Multi-select (bulk delete/forward, user request).
  final Set<int> selected;

  final String? error;

  /// Bumped when cache data the screen shows changes (read state, typing,
  /// users) without the message list changing.
  final int revision;

  bool get selecting => selected.isNotEmpty;

  ConversationState copyWith({
    td.Chat? chat,
    List<td.Message>? messages,
    bool? initialLoading,
    bool? loadingOlder,
    bool? loadingNewer,
    bool? hasOlder,
    bool? hasNewer,
    int? Function()? firstUnreadId,
    ({int messageId, int serial})? Function()? anchor,
    int? Function()? highlightId,
    td.Message? Function()? replyTo,
    td.Message? Function()? editing,
    td.Message? Function()? pinned,
    Set<int>? selected,
    String? Function()? error,
    int? revision,
  }) => ConversationState(
    chatId: chatId,
    chat: chat ?? this.chat,
    messages: messages ?? this.messages,
    initialLoading: initialLoading ?? this.initialLoading,
    loadingOlder: loadingOlder ?? this.loadingOlder,
    loadingNewer: loadingNewer ?? this.loadingNewer,
    hasOlder: hasOlder ?? this.hasOlder,
    hasNewer: hasNewer ?? this.hasNewer,
    firstUnreadId: firstUnreadId != null ? firstUnreadId() : this.firstUnreadId,
    anchor: anchor != null ? anchor() : this.anchor,
    highlightId: highlightId != null ? highlightId() : this.highlightId,
    replyTo: replyTo != null ? replyTo() : this.replyTo,
    editing: editing != null ? editing() : this.editing,
    pinned: pinned != null ? pinned() : this.pinned,
    selected: selected ?? this.selected,
    error: error != null ? error() : this.error,
    revision: revision ?? this.revision,
  );
}
