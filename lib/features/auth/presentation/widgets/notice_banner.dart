import 'package:flutter/material.dart';

import '../../../../core/theme/glow_colors.dart';

/// Informational message (e.g. "Your session ended"), announced on arrival.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.text, this.onDismiss});

  final String text;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 4, 0, 4),
        decoration: BoxDecoration(
          color: GlowColors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: GlowColors.amber.withValues(alpha: 0.6)),
          boxShadow: glow(GlowColors.amber, intensity: 0.2),
        ),
        child: Row(
          children: [
            Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.35))),
            if (onDismiss != null)
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded, size: 18),
                color: GlowColors.textMuted,
                tooltip: 'Dismiss',
              ),
          ],
        ),
      ),
    );
  }
}
