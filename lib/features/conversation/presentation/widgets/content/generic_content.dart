import 'package:flutter/material.dart';
import 'package:handy_tdlib_next/api.dart' as td;

/// Icon + one-line description for content without a dedicated renderer.
class GenericContent extends StatelessWidget {
  const GenericContent({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
    required this.mutedColor,
    required this.footer,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final Color mutedColor;
  final Widget footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
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
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.12)),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(color: color, fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null)
                        Text(subtitle!, style: TextStyle(color: mutedColor, fontSize: 12)),
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

IconData genericIcon(td.MessageContent c) => switch (c) {
  td.MessagePhoto() || td.MessageExpiredPhoto() => Icons.image_rounded,
  td.MessageVideo() || td.MessageExpiredVideo() || td.MessageAnimation() => Icons.movie_rounded,
  td.MessageDocument() => Icons.insert_drive_file_rounded,
  td.MessageAudio() => Icons.music_note_rounded,
  td.MessageVoiceNote() || td.MessageExpiredVoiceNote() => Icons.mic_rounded,
  td.MessageVideoNote() || td.MessageExpiredVideoNote() => Icons.videocam_rounded,
  td.MessagePoll() => Icons.poll_rounded,
  td.MessageContact() => Icons.person_rounded,
  td.MessageLocation() || td.MessageVenue() => Icons.place_rounded,
  td.MessageCall() => Icons.call_rounded,
  td.MessageSticker() => Icons.emoji_emotions_rounded,
  _ => Icons.help_outline_rounded,
};
