import 'package:flutter/widgets.dart';
import 'package:lumina_tdlib/api.dart' as td;

/// Lets other features decorate a chat row's avatar (story halos) without
/// the chat list depending on them. Provided by the composition root.
class ChatRowExtensions {
  const ChatRowExtensions();

  /// Rebuilds rows when it fires (e.g. stories changed).
  Listenable? get listenable => null;

  /// [avatar] is [size] wide; the result should be `size + 8` wide so rows
  /// line up whether or not they are decorated.
  Widget avatar(BuildContext context, td.Chat chat, Widget avatar, double size) =>
      Padding(padding: const EdgeInsets.all(4), child: avatar);
}
