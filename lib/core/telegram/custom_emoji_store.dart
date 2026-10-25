import 'dart:async';

import 'package:handy_tdlib_next/api.dart' as td;

import '../tdlib/td_client.dart';

/// Resolves custom emoji ids to stickers, batching lookups made in the
/// same frame (a message often has several).
class CustomEmojiStore {
  CustomEmojiStore(this._client);

  final TdClient _client;
  final _known = <int, td.Sticker?>{};
  final _waiting = <int, Completer<td.Sticker?>>{};
  Timer? _flush;

  td.Sticker? cached(int id) => _known[id];

  Future<td.Sticker?> get(int id) {
    if (_known.containsKey(id)) return Future.value(_known[id]);
    final c = _waiting.putIfAbsent(id, Completer.new);
    _flush ??= Timer(Duration.zero, _load);
    return c.future;
  }

  Future<void> _load() async {
    _flush = null;
    final batch = Map.of(_waiting);
    _waiting.clear();
    try {
      // TDLib accepts up to 200 ids per call.
      final ids = batch.keys.toList();
      for (var i = 0; i < ids.length; i += 200) {
        final chunk = ids.sublist(i, (i + 200).clamp(0, ids.length));
        final r = await _client.invoke<td.Stickers>(td.GetCustomEmojiStickers(customEmojiIds: chunk));
        for (final s in r.stickers) {
          if (s.fullType case td.StickerFullTypeCustomEmoji(:final customEmojiId)) _known[customEmojiId] = s;
        }
      }
    } catch (_) {
      // Fall back to the plain emoji.
    }
    for (final MapEntry(key: id, value: c) in batch.entries) {
      _known.putIfAbsent(id, () => null);
      c.complete(_known[id]);
    }
  }
}
