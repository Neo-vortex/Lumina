import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lottie/lottie.dart';

import 'lottie_frame_cache.dart';

import 'package:lumina_tdlib/api.dart' as td;

import '../../storage/app_preferences.dart';
import '../file_store.dart';
import 'file_progress.dart';
import 'td_file_image.dart';

/// Telegram's TGS stickers are gzipped Lottie JSON.
Future<LottieComposition?> decodeTgs(List<int> bytes) => LottieComposition.fromBytes(gzip.decode(bytes));

/// An animated emoji, reaction or sticker. TGS plays through Lottie (once
/// by default, so it rests afterwards); other formats, a missing file, or
/// "animated emoji" switched off in Settings show the static thumbnail or
/// the plain emoji.
class AnimatedSticker extends StatelessWidget {
  const AnimatedSticker({
    super.key,
    required this.sticker,
    required this.size,
    this.repeat = false,
    this.autoplay = true,
  });

  final td.Sticker sticker;
  final double size;
  final bool repeat;

  /// Off: hold the first frame (emoji-only messages play when tapped).
  final bool autoplay;

  @override
  Widget build(BuildContext context) {
    final emoji = Center(
      child: Text(sticker.emoji, style: TextStyle(fontSize: size * 0.8, height: 1)),
    );
    if (!context.read<AppPreferences>().animatedEmoji) {
      return SizedBox.square(dimension: size, child: emoji);
    }
    final fallback = sticker.thumbnail != null
        ? TdFileImage(file: sticker.thumbnail!.file, fit: BoxFit.contain, semanticLabel: sticker.emoji)
        : emoji;
    return SizedBox.square(
      dimension: size,
      child: switch (sticker.format) {
        td.StickerFormatWebp() => TdFileImage(
          file: sticker.sticker,
          fit: BoxFit.contain,
          semanticLabel: sticker.emoji,
        ),
        // WebM would need a video decoder per emoji; its thumbnail for now.
        td.StickerFormatWebm() => fallback,
        td.StickerFormatTgs() => FileBuilder(
          file: sticker.sticker,
          builder: (context, f) => f.isDownloaded && f.local.path.isNotEmpty
              // Looping ones (custom emoji in text) from pre-drawn frames: many
              // live Lottie players at once stuttered and flickered.
              ? repeat && autoplay
                    ? CachedLottie(path: f.local.path, size: size, placeholder: fallback)
                    : Lottie.file(
                        File(f.local.path),
                        decoder: decodeTgs,
                        repeat: repeat,
                        animate: autoplay,
                        width: size,
                        height: size,
                        frameBuilder: (context, child, composition) => composition == null ? fallback : child,
                      )
              : _Download(file: f, child: fallback),
        ),
      },
    );
  }
}

/// Starts the (small) download once, showing [child] meanwhile.
class _Download extends StatefulWidget {
  const _Download({required this.file, required this.child});

  final td.File file;
  final Widget child;

  @override
  State<_Download> createState() => _DownloadState();
}

class _DownloadState extends State<_Download> {
  @override
  void initState() {
    super.initState();
    final f = widget.file;
    if (f.local.canBeDownloaded && !f.local.isDownloadingActive) {
      context.read<FileStore>().download(f.id, priority: 12).ignore();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
