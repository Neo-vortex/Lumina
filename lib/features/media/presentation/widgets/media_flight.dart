import 'package:flutter/widgets.dart';

/// Links chat media tiles to the viewer's open and close flights, in place
/// of a Hero: the viewer asks where a message's tile is, and hides that tile
/// while the picture flies, so the chat never remounts or swaps an image.
class MediaFlight {
  MediaFlight._();

  static final _tiles = <int, GlobalKey>{};

  /// The message whose tile is hidden (the picture is in flight or the
  /// viewer is being dragged away from over it).
  static final hidden = ValueNotifier<int?>(null);

  static void register(int messageId, GlobalKey key) => _tiles[messageId] = key;

  static void unregister(int messageId, GlobalKey key) {
    if (_tiles[messageId] == key) _tiles.remove(messageId);
  }

  /// The tile's rect on screen, or null when it isn't laid out on screen.
  static Rect? rectOf(int messageId) {
    final box = _tiles[messageId]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}
