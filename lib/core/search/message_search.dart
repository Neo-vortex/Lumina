/// A search hit from the local full-text index.
class MessageHit {
  const MessageHit({
    required this.chatId,
    required this.messageId,
    required this.date,
    required this.snippet,
  });

  final int chatId;
  final int messageId;
  final int date;

  /// Matching excerpt with matches wrapped in `[[` `]]`.
  final String snippet;
}

/// Local full-text message search, implemented by the search feature and
/// consumed by any screen that searches messages.
abstract interface class MessageSearch {
  /// Best matches first. [chatId] restricts to one chat.
  Future<List<MessageHit>> search(String query, {int? chatId, int limit = 100});

  bool get enabled;
}
