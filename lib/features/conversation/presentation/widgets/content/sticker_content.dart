import 'package:flutter/material.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../../../core/telegram/widgets/td_file_image.dart';

/// Static stickers render directly (WebP); animated ones (TGS/WebM) show
/// their thumbnail.
class StickerContent extends StatelessWidget {
  const StickerContent({super.key, required this.sticker, required this.footer});

  final td.Sticker sticker;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final file = sticker.format is td.StickerFormatWebp ? sticker.sticker : sticker.thumbnail?.file;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 160,
            child: file == null
                ? Center(child: Text(sticker.emoji, style: const TextStyle(fontSize: 64)))
                : TdFileImage(file: file, fit: BoxFit.contain, semanticLabel: '${sticker.emoji} sticker'),
          ),
          footer,
        ],
      ),
    );
  }
}
