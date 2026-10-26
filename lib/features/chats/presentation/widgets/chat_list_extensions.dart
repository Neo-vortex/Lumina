import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// Lets other features add buttons to the chat list's header (the proxy
/// switch) without the chat list depending on them. Provided by the
/// composition root.
class ChatListExtensions {
  const ChatListExtensions();

  static ChatListExtensions of(BuildContext context) {
    try {
      return context.read<ChatListExtensions>();
    } on ProviderNotFoundException {
      return const ChatListExtensions();
    }
  }

  /// Shown before the search button.
  List<Widget> headerActions(BuildContext context) => const [];
}
