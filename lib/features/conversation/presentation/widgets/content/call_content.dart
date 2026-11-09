import 'package:flutter/material.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../../core/telegram/display.dart';
import '../../../../../core/theme/glow_colors.dart';

/// A call in the history: an arrow for its direction (red when missed), what
/// happened, and how long it lasted.
class CallContent extends StatelessWidget {
  const CallContent({
    super.key,
    required this.message,
    required this.color,
    required this.mutedColor,
    required this.footer,
  });

  final td.Message message;
  final Color color;
  final Color mutedColor;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final call = Display.call(message);
    final video = (message.content as td.MessageCall).isVideo;
    final accent = call.missed ? GlowColors.error : GlowColors.cyan;
    return Semantics(
      label: [call.title, ?call.detail].join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: 0.14)),
                  child: Icon(video ? Icons.videocam_rounded : Icons.call_rounded, color: accent, size: 21),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        call.title,
                        style: TextStyle(color: color, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            call.outgoing ? Icons.call_made_rounded : Icons.call_received_rounded,
                            size: 14,
                            color: call.missed ? GlowColors.error : GlowColors.cyan,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            call.detail ?? (call.outgoing ? 'Outgoing' : 'Incoming'),
                            style: TextStyle(color: mutedColor, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            footer,
          ],
        ),
      ),
    );
  }
}
