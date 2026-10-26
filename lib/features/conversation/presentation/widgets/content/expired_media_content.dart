import 'package:flutter/material.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../../core/theme/glow_colors.dart';

/// A self-destructed photo, video or voice/video message: what it was, and
/// that it disappeared after being opened (Telegram's timer starts on open).
class ExpiredMediaContent extends StatelessWidget {
  const ExpiredMediaContent({
    super.key,
    required this.content,
    required this.outgoing,
    required this.color,
    required this.footer,
  });

  final td.MessageContent content;
  final bool outgoing;
  final Color color;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final (kind, icon) = switch (content) {
      td.MessageExpiredVideo() => ('video', Icons.videocam_off_rounded),
      td.MessageExpiredVoiceNote() => ('voice message', Icons.mic_off_rounded),
      td.MessageExpiredVideoNote() => ('video message', Icons.videocam_off_rounded),
      _ => ('photo', Icons.hide_image_rounded),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // An ember: the media burnt away.
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      GlowColors.amber.withValues(alpha: 0.35),
                      GlowColors.coral.withValues(alpha: 0.08),
                    ],
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(icon, color: color.withValues(alpha: 0.85), size: 20),
                    const Positioned(
                      right: 4,
                      bottom: 3,
                      child: Icon(Icons.local_fire_department_rounded, color: GlowColors.amber, size: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Disappearing $kind',
                      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    Text(
                      outgoing ? 'Opened, and gone for good' : 'You opened it — it\'s gone now',
                      style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 13),
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
    );
  }
}
