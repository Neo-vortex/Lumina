import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/display.dart';
import '../../../core/telegram/telegram_cache.dart';
import '../../../core/telegram/widgets/td_file_image.dart';
import '../../../core/theme/glow_colors.dart';
import '../domain/download_item.dart';

/// What a row says about its download right now.
enum DownloadStatus { downloading, paused, waitingForWifi, failed, done }

DownloadStatus statusOf(DownloadItem i, {required bool waitingForWifi}) {
  if (i.isCompleted) return DownloadStatus.done;
  if (waitingForWifi) return DownloadStatus.waitingForWifi;
  if (i.isPaused) return DownloadStatus.paused;
  final f = i.file;
  // TDLib stopped on its own (e.g. no space) before finishing.
  if (f != null && !f.local.isDownloadingActive && i.size > 0 && i.downloaded < i.size) {
    return DownloadStatus.failed;
  }
  return DownloadStatus.downloading;
}

/// A small preview of the message's media, or null.
td.File? thumbnailOf(td.MessageContent c) => switch (c) {
  td.MessagePhoto(:final photo) => photo.sizes.firstOrNull?.photo,
  td.MessageVideo(:final video) => video.thumbnail?.file,
  td.MessageAnimation(:final animation) => animation.thumbnail?.file,
  td.MessageDocument(:final document) => document.thumbnail?.file,
  td.MessageAudio(:final audio) => audio.albumCoverThumbnail?.file,
  td.MessageVideoNote(:final videoNote) => videoNote.thumbnail?.file,
  _ => null,
};

/// One download: preview, name, chat, size and progress, and its action.
class DownloadRow extends StatelessWidget {
  const DownloadRow({
    super.key,
    required this.item,
    required this.status,
    required this.wifiOnly,
    required this.bytesPerSecond,
    required this.onToggle,
    required this.onOpen,
    required this.onOpenChat,
    required this.onRetry,
    required this.onLongPress,
    this.dragHandle,
  });

  final DownloadItem item;
  final DownloadStatus status;
  final bool wifiOnly;
  final int bytesPerSecond;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final VoidCallback onOpenChat;
  final VoidCallback onRetry;
  final VoidCallback onLongPress;
  final Widget? dragHandle;

  static const _icons = {
    DownloadFilter.videos: Icons.movie_rounded,
    DownloadFilter.music: Icons.music_note_rounded,
    DownloadFilter.photos: Icons.photo_rounded,
    DownloadFilter.files: Icons.description_rounded,
    DownloadFilter.all: Icons.description_rounded,
  };

  String get _statusText => switch (status) {
    DownloadStatus.downloading =>
      bytesPerSecond > 0 ? '${Display.fileSize(bytesPerSecond)}/s' : 'Downloading',
    DownloadStatus.paused => 'Paused',
    DownloadStatus.waitingForWifi => 'Waiting for Wi-Fi',
    DownloadStatus.failed => 'Failed',
    DownloadStatus.done => 'Done',
  };

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final chat = cache.chats[item.message.chatId]?.title ?? '';
    final thumb = thumbnailOf(item.message.content);
    final size = item.size;
    final progress = size > 0 ? (item.downloaded / size).clamp(0.0, 1.0) : null;
    final accent = switch (status) {
      DownloadStatus.failed => GlowColors.error,
      DownloadStatus.paused || DownloadStatus.waitingForWifi => GlowColors.amber,
      _ => GlowColors.cyan,
    };
    return InkWell(
      onTap: status == DownloadStatus.done ? onOpen : null,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox.square(
                dimension: 48,
                child: thumb != null
                    ? TdFileImage(file: thumb, priority: 1)
                    : ColoredBox(
                        color: GlowColors.surfaceHigh,
                        child: Icon(_icons[item.kind], color: GlowColors.textMuted),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                      ),
                      if (wifiOnly) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.wifi_rounded, size: 14, color: GlowColors.cyan),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: onOpenChat,
                    child: Text(
                      [
                        if (chat.isNotEmpty) chat,
                        if (size > 0) Display.fileSize(size),
                        if (status != DownloadStatus.done) _statusText,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: GlowColors.textMuted, fontSize: 12),
                    ),
                  ),
                  if (status != DownloadStatus.done && progress != null) ...[
                    const SizedBox(height: 6),
                    _GlowBar(value: progress, color: accent),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            switch (status) {
              DownloadStatus.done => IconButton(
                tooltip: 'Open',
                icon: const Icon(Icons.open_in_new_rounded, color: GlowColors.textMuted),
                onPressed: onOpen,
              ),
              DownloadStatus.failed => IconButton(
                tooltip: 'Retry',
                icon: const Icon(Icons.refresh_rounded, color: GlowColors.error),
                onPressed: onRetry,
              ),
              DownloadStatus.paused => IconButton(
                tooltip: 'Resume',
                icon: Icon(Icons.play_arrow_rounded, color: accent),
                onPressed: onToggle,
              ),
              _ => IconButton(
                tooltip: 'Pause',
                icon: Icon(Icons.pause_rounded, color: accent),
                onPressed: onToggle,
              ),
            },
            ?dragHandle,
          ],
        ),
      ),
    );
  }
}

class _GlowBar extends StatelessWidget {
  const _GlowBar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    height: 4,
    decoration: BoxDecoration(color: GlowColors.outline, borderRadius: BorderRadius.circular(2)),
    alignment: Alignment.centerLeft,
    child: FractionallySizedBox(
      widthFactor: value,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
          boxShadow: glow(color, intensity: 0.4),
        ),
      ),
    ),
  );
}
