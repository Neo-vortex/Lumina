import 'dart:async';

import 'package:flutter/foundation.dart';

/// Whether the chat's message list is moving. Heavy things wait for a pause:
/// liquid glass falls back to a blur, GIFs hold their still frame (and start
/// only once the reader has settled on them).
abstract final class ChatScrolling {
  static final moving = ValueNotifier<bool>(false);
  static Timer? _settle;

  /// Call on scroll start / end. "Still" a moment after the last scroll ends,
  /// so a run of flings doesn't flicker.
  static void set(bool scrolling) {
    _settle?.cancel();
    if (scrolling) {
      moving.value = true;
    } else {
      _settle = Timer(const Duration(milliseconds: 220), () => moving.value = false);
    }
  }
}
