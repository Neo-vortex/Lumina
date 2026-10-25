import 'package:flutter/widgets.dart';

/// Opens the chat message a story was made from (`StoryAreaTypeMessage`).
/// The conversation lives in another feature, so the app supplies it.
class StoryMessageOpener {
  const StoryMessageOpener(this.open);

  final Future<void> Function(BuildContext context, int chatId, int messageId) open;
}
