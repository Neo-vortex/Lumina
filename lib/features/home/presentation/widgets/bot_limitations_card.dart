import 'package:flutter/material.dart';

import '../../../../core/theme/glow_colors.dart';

/// Shown right after a bot logs in (spec §4.1).
class BotLimitationsCard extends StatelessWidget {
  const BotLimitationsCard(this.limitations, {super.key});

  final List<String> limitations;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: GlowColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GlowColors.cyan.withValues(alpha: 0.4)),
        boxShadow: glow(GlowColors.cyan, intensity: 0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Signed in as a bot', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Telegram limits what bot accounts can do:',
            style: TextStyle(color: GlowColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          for (final line in limitations)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 7, right: 10),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: GlowColors.cyan,
                      boxShadow: glow(GlowColors.cyan),
                    ),
                  ),
                  Expanded(child: Text(line, style: const TextStyle(fontSize: 14, height: 1.35))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
