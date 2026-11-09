import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/td_file_image.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/lumina_glass.dart';
import 'content/media_content.dart';

/// Pinned message banner (spec §6.2); tap jumps to the message.
class PinnedBanner extends StatelessWidget {
  const PinnedBanner({super.key, required this.message, required this.onTap, this.onUnpin});

  final td.Message message;
  final VoidCallback onTap;
  final VoidCallback? onUnpin;

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final visual = visualOf(message.content);
    // A glass card floating under the header, not a solid band.
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
      child: LuminaGlass(
        grouped: true,
        shadow: false,
        radius: 18,
        tintOpacity: 0.5,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 7, 4, 7),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 34,
                    decoration: BoxDecoration(
                      color: GlowColors.violet,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (visual != null && (visual.file != null || visual.mini != null)) ...[
                    _Thumb(file: visual.file, mini: visual.mini, isVideo: visual.isVideo),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Pinned message',
                          style: TextStyle(
                            color: GlowColors.violet,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          Display.preview(cache, message),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  if (onUnpin != null)
                    IconButton(
                      tooltip: 'Unpin',
                      icon: const Icon(Icons.close_rounded, size: 18, color: GlowColors.textMuted),
                      onPressed: onUnpin,
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

/// A small rounded preview of a pinned photo or video.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.file, required this.mini, required this.isVideo});

  final td.File? file;
  final td.Minithumbnail? mini;
  final bool isVideo;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox.square(
      dimension: 36,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (file != null)
            TdFileImage(file: file!, placeholderBytes: Display.minithumbnail(mini), priority: 2)
          else
            Image.memory(
              Display.minithumbnail(mini)!,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
            ),
          if (isVideo)
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black45),
                child: Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
              ),
            ),
        ],
      ),
    ),
  );
}
