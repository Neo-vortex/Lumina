import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;
import 'package:open_filex/open_filex.dart';

import '../../../../../core/telegram/display.dart';
import '../../../../../core/telegram/file_store.dart';
import '../../../../../core/telegram/widgets/file_progress.dart';
import '../../../../../core/telegram/widgets/formatted_text_view.dart';
import '../../../../../core/telegram/widgets/td_file_image.dart';
import '../../../../../core/theme/glow_colors.dart';

/// A file: icon or thumbnail, name, size / progress. Tap downloads, then
/// opens with the system handler.
class DocumentContent extends StatelessWidget {
  const DocumentContent({
    super.key,
    required this.document,
    required this.caption,
    required this.textColor,
    required this.mutedColor,
    required this.footer,
  });

  final td.Document document;
  final td.FormattedText caption;
  final Color textColor;
  final Color mutedColor;
  final Widget footer;

  Future<void> _tap(BuildContext context, td.File f) async {
    final store = context.read<FileStore>();
    if (f.isDownloaded) {
      final result = await OpenFilex.open(
        f.local.path,
        type: document.mimeType.isEmpty ? null : document.mimeType,
      );
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No app can open this file (${result.message})')));
      }
    } else if (f.isDownloading) {
      await store.cancel(f.id);
    } else {
      await store.download(f.id, priority: 24);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FileBuilder(
      file: document.document,
      builder: (context, f) {
        final p = f.progress;
        final ext = document.fileName.contains('.')
            ? document.fileName.split('.').last.toUpperCase()
            : 'FILE';
        return InkWell(
          onTap: () => _tap(context, f),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 48,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: textColor.withValues(alpha: 0.12),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: document.thumbnail != null
                                ? TdFileImage(
                                    file: document.thumbnail!.file,
                                    placeholderBytes: Display.minithumbnail(document.minithumbnail),
                                  )
                                : Center(
                                    child: Text(
                                      ext.length > 4 ? ext.substring(0, 4) : ext,
                                      style: TextStyle(
                                        color: textColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                          ),
                          if (f.isDownloading || f.isUploading)
                            CircularProgressIndicator(value: p, strokeWidth: 2.4, color: GlowColors.cyan),
                          if (!f.isDownloaded && !f.isDownloading && !f.isUploading)
                            Icon(Icons.download_rounded, color: textColor),
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
                            document.fileName.isEmpty ? 'File' : document.fileName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            p != null
                                ? '${Display.fileSize((p * f.totalSize).round())} / ${Display.fileSize(f.totalSize)}'
                                : Display.fileSize(f.totalSize),
                            style: TextStyle(color: mutedColor, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (caption.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: FormattedTextView(caption, style: TextStyle(color: textColor, fontSize: 15)),
                  ),
                const SizedBox(height: 4),
                footer,
              ],
            ),
          ),
        );
      },
    );
  }
}
