import 'package:flutter/material.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../../core/theme/glow_colors.dart';

/// Reaction chips under a bubble; tap toggles your own reaction.
class ReactionsRow extends StatelessWidget {
  const ReactionsRow({super.key, required this.reactions, required this.onTap});

  final List<td.MessageReaction> reactions;
  final void Function(String emoji) onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final r in reactions)
          if (r.type case td.ReactionTypeEmoji(:final emoji))
            Semantics(
              button: true,
              selected: r.isChosen,
              label: '$emoji ${r.totalCount}',
              excludeSemantics: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onTap(emoji),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 32, minWidth: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: r.isChosen
                        ? GlowColors.violetDeep.withValues(alpha: 0.55)
                        : GlowColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: r.isChosen ? GlowColors.violet : GlowColors.outline),
                    boxShadow: r.isChosen ? glow(GlowColors.violet, intensity: 0.3) : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 15)),
                      const SizedBox(width: 4),
                      Text(
                        '${r.totalCount}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
