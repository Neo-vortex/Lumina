import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../tdlib/td_client.dart';
import 'telegram_cache.dart';
import 'widgets/animated_sticker.dart';

/// Message effects (🎉 🔥 ❤️… played over a message when it arrives): the
/// ones this account may send, and playing one over the screen.
abstract final class MessageEffects {
  static final _cache = <int, Future<td.MessageEffect?>>{};

  static Future<td.MessageEffect?> get(BuildContext context, int id) {
    final client = context.read<TdClient>();
    return _cache[id] ??= client
        .invoke<td.MessageEffect>(td.GetMessageEffect(effectId: id))
        .then<td.MessageEffect?>((e) => e)
        .catchError((Object _) => null);
  }

  /// The effects offered for sending (free ones, in Telegram's order).
  static Future<List<td.MessageEffect>> available(BuildContext context) async {
    final ids = context.read<TelegramCache>().messageEffectIds;
    final all = await Future.wait([for (final id in ids) get(context, id)]);
    return [
      for (final e in all)
        if (e != null && !e.isPremium) e,
    ];
  }

  /// The big animation an effect plays.
  static td.Sticker? animationOf(td.MessageEffect e) => switch (e.type) {
    td.MessageEffectTypeEmojiReaction(:final effectAnimation) => effectAnimation,
    td.MessageEffectTypePremiumSticker(:final sticker) => sticker,
  };

  /// Plays [effectId] once over [around] (the message's bubble), above
  /// everything, then removes itself.
  static Future<void> play(BuildContext context, int effectId, Rect around) async {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final effect = await get(context, effectId);
    final sticker = effect == null ? null : animationOf(effect);
    if (overlay == null || sticker == null || !context.mounted) return;
    final size = (MediaQuery.sizeOf(context).shortestSide * 0.9).clamp(200.0, 420.0);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        left: around.center.dx - size / 2,
        top: around.center.dy - size / 2,
        child: IgnorePointer(
          child: AnimatedSticker(sticker: sticker, size: size),
        ),
      ),
    );
    overlay.insert(entry);
    await Future<void>.delayed(const Duration(milliseconds: 2800));
    entry.remove();
  }
}
