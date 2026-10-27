import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/widgets/animated_sticker.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';
import '../../data/messages_repository.dart';

/// Reaction chips under a bubble; tap toggles your own reaction.
///
/// Nothing is faked: a tapped chip glows while TDLib works, and only its
/// answer changes the count, together with the full effect.
class ReactionsRow extends StatelessWidget {
  const ReactionsRow({
    super.key,
    required this.reactions,
    required this.onTap,
    this.pending = const {},
    this.burst,
  });

  final List<td.MessageReaction> reactions;
  final void Function(String emoji) onTap;

  /// Emoji (no variation selector) waiting for TDLib's answer.
  final Set<String> pending;

  /// The reaction TDLib just confirmed: its chip plays the effect once.
  final ({String emoji, int serial})? burst;

  static String _plain(String e) => e.replaceAll('️', '');

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final r in reactions)
          if (r.type case td.ReactionTypeEmoji(:final emoji))
            ReactionChip(
              key: ValueKey(_plain(emoji)),
              emoji: emoji,
              count: r.totalCount,
              chosen: r.isChosen,
              pending: pending.contains(_plain(emoji)),
              burst: burst != null && _plain(burst!.emoji) == _plain(emoji) ? burst!.serial : null,
              onTap: () => onTap(emoji),
            ),
      ],
    );
  }
}

class ReactionChip extends StatefulWidget {
  const ReactionChip({
    super.key,
    required this.emoji,
    required this.count,
    required this.chosen,
    required this.pending,
    required this.burst,
    required this.onTap,
  });

  final String emoji;
  final int count;
  final bool chosen;
  final bool pending;

  /// Serial of a confirmed reaction to celebrate; each plays once.
  final int? burst;
  final VoidCallback onTap;

  @override
  State<ReactionChip> createState() => _ReactionChipState();
}

class _ReactionChipState extends State<ReactionChip> with SingleTickerProviderStateMixin {
  /// Breathes while the request is in flight (well under a second usually).
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  int? _played;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ReactionChip old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.pending && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.pending && _pulse.isAnimating) {
      _pulse.animateTo(0, duration: const Duration(milliseconds: 220));
    }
    final burst = widget.burst;
    if (burst != null && burst != _played) {
      _played = burst;
      if (Motion.ambientEnabled(context)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _portal.show();
        });
      }
    } else if (burst == null && _portal.isShowing) {
      _portal.hide();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: widget.chosen,
      label: '${widget.emoji} ${widget.count}${widget.pending ? ', sending' : ''}',
      excludeSemantics: true,
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => _Burst(link: _link, emoji: widget.emoji, onDone: _portal.hide),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: widget.onTap,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(_pulse.value);
                return Container(
                  constraints: const BoxConstraints(minHeight: 32, minWidth: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.chosen
                        ? GlowColors.violetDeep.withValues(alpha: 0.55)
                        : GlowColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Color.lerp(
                        widget.chosen ? GlowColors.violet : GlowColors.outline,
                        GlowColors.cyan,
                        t,
                      )!,
                      width: 1 + 0.6 * t,
                    ),
                    boxShadow: [
                      if (widget.chosen) ...glow(GlowColors.violet, intensity: 0.3),
                      if (t > 0) ...glow(GlowColors.cyan, intensity: 0.4 + 0.6 * t),
                    ],
                  ),
                  child: child,
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.emoji, style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Text(
                      '${widget.count}',
                      key: ValueKey(widget.count),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Telegram's full reaction effect over the chip: the centre animation and
/// the splash around it, played once, above everything (no clipping by
/// neighbouring bubbles).
class _Burst extends StatefulWidget {
  const _Burst({required this.link, required this.emoji, required this.onDone});

  final LayerLink link;
  final String emoji;
  final VoidCallback onDone;

  @override
  State<_Burst> createState() => _BurstState();
}

class _BurstState extends State<_Burst> {
  static const _center = 48.0, _around = 150.0;
  late final Future<td.EmojiReaction?> _reaction = context.read<MessagesRepository>().emojiReaction(
    widget.emoji,
  );

  @override
  void initState() {
    super.initState();
    // The effect runs about 2 s; the overlay goes with it.
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (mounted) widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: widget.link,
        // Centred on the chip's emoji (its left part).
        targetAnchor: const Alignment(-0.45, 0),
        followerAnchor: Alignment.center,
        child: IgnorePointer(
          child: SizedBox.square(
            dimension: _around,
            child: FutureBuilder<td.EmojiReaction?>(
              future: _reaction,
              builder: (context, snap) {
                final r = snap.data;
                if (r == null) return const SizedBox.shrink();
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Telegram's tap effect: the splash around, the emoji's
                    // own activation (the heart spins) in the middle.
                    AnimatedSticker(sticker: r.effectAnimation, size: _around),
                    AnimatedSticker(sticker: r.activateAnimation, size: _center),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
