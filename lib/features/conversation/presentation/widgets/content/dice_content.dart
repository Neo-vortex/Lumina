import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../../core/telegram/widgets/animated_sticker.dart';
import '../../../../../core/theme/glow_colors.dart';

/// A dice-style game message (🎲 🎯 🏀 ⚽ 🎳 🎰). With Telegram's dice
/// stickers (TDLib's final state) their animation plays; on servers without
/// them, Lumina's own roll: the emoji tumbles in, then the result settles
/// (a die face for 🎲, the outcome for the others). The value is the
/// server's, never the client's.
class DiceContent extends StatefulWidget {
  const DiceContent({super.key, required this.dice, required this.footer, this.animate = true});

  final td.MessageDice dice;
  final Widget footer;

  /// Roll on first sight; old messages show the result straight away.
  final bool animate;

  @override
  State<DiceContent> createState() => _DiceContentState();
}

class _DiceContentState extends State<DiceContent> with SingleTickerProviderStateMixin {
  late final _roll = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
    ..value = widget.animate ? 0 : 1;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _roll.forward();
  }

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  String get _emoji => widget.dice.emoji.replaceAll('️', '');

  int get _value => widget.dice.value;

  /// Telegram's outcomes per game.
  (String, bool) get _outcome => switch (_emoji) {
    '🎲' => ('Rolled $_value', _value == 6),
    '🎯' => (
      _value == 6
          ? 'Bullseye!'
          : _value == 1
          ? 'Missed the board'
          : 'Hit · $_value/6',
      _value == 6,
    ),
    '🏀' => (_value >= 4 ? 'Scored!' : 'Missed', _value >= 4),
    '⚽' => (_value >= 3 ? 'Goal!' : 'Missed', _value >= 3),
    '🎳' => (
      switch (_value) {
        6 => 'Strike!',
        1 => 'Gutter ball',
        2 => '1 pin',
        3 => '3 pins',
        4 => '4 pins',
        _ => '5 pins',
      },
      _value == 6,
    ),
    '🎰' => (
      _value == 64
          ? 'Jackpot! 7️⃣7️⃣7️⃣'
          : (_value == 1 || _value == 22 || _value == 43)
          ? 'Three of a kind!'
          : 'Try again',
      _value == 64 || _value == 1 || _value == 22 || _value == 43,
    ),
    _ => ('$_value', false),
  };

  @override
  Widget build(BuildContext context) {
    final sticker = switch (widget.dice.finalState) {
      td.DiceStickersRegular(:final sticker) => sticker,
      _ => null,
    };
    final (label, win) = _outcome;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox.square(
          dimension: 140,
          child: sticker != null
              ? AnimatedSticker(sticker: sticker, size: 140)
              : AnimatedBuilder(
                  animation: _roll,
                  builder: (context, _) {
                    final t = Curves.easeOutBack.transform(_roll.value.clamp(0.0, 1.0));
                    final spin = (1 - _roll.value) * 4 * math.pi;
                    final settled = _roll.value >= 0.85;
                    return Center(
                      child: Transform.rotate(
                        angle: spin,
                        child: Transform.scale(
                          scale: 0.4 + 0.6 * t,
                          child: _emoji == '🎲' && settled
                              ? _DieFace(value: _value, size: 96)
                              : Text(_emoji, style: const TextStyle(fontSize: 84)),
                        ),
                      ),
                    );
                  },
                ),
        ),
        FadeTransition(
          opacity: CurvedAnimation(parent: _roll, curve: const Interval(0.8, 1)),
          child: Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (win ? GlowColors.amber : GlowColors.surfaceHigh).withValues(alpha: win ? 0.25 : 0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: win ? GlowColors.amber.withValues(alpha: 0.6) : GlowColors.outline),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: win ? GlowColors.amber : GlowColors.text,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        widget.footer,
      ],
    );
  }
}

/// A white die showing [value] pips.
class _DieFace extends StatelessWidget {
  const _DieFace({required this.value, required this.size});

  final int value;
  final double size;

  static const _pips = <int, List<(double, double)>>{
    1: [(0.5, 0.5)],
    2: [(0.27, 0.27), (0.73, 0.73)],
    3: [(0.27, 0.27), (0.5, 0.5), (0.73, 0.73)],
    4: [(0.27, 0.27), (0.73, 0.27), (0.27, 0.73), (0.73, 0.73)],
    5: [(0.27, 0.27), (0.73, 0.27), (0.5, 0.5), (0.27, 0.73), (0.73, 0.73)],
    6: [(0.27, 0.25), (0.73, 0.25), (0.27, 0.5), (0.73, 0.5), (0.27, 0.75), (0.73, 0.75)],
  };

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFE3E6EE)],
      ),
      borderRadius: BorderRadius.circular(size * 0.2),
      boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 12, offset: Offset(0, 5))],
    ),
    child: Stack(
      children: [
        for (final (x, y) in _pips[value.clamp(1, 6)]!)
          Positioned(
            left: x * size - size * 0.08,
            top: y * size - size * 0.08,
            child: Container(
              width: size * 0.16,
              height: size * 0.16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value == 1 ? const Color(0xFFD7263D) : const Color(0xFF1C1F2A),
              ),
            ),
          ),
      ],
    ),
  );
}
