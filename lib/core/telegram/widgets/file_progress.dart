import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../theme/glow_colors.dart';
import '../display.dart';
import '../file_store.dart';

/// Rebuilds with the latest state of a TDLib file.
class FileBuilder extends StatelessWidget {
  const FileBuilder({super.key, required this.file, required this.builder});

  final td.File file;
  final Widget Function(BuildContext context, td.File file) builder;

  @override
  Widget build(BuildContext context) {
    final store = context.read<FileStore>();
    return StreamBuilder<td.File>(
      stream: store.watch(file.id),
      initialData: store[file.id] ?? file,
      builder: (context, snap) => builder(context, snap.data!),
    );
  }
}

extension FileProgressX on td.File {
  int get totalSize => size != 0 ? size : expectedSize;
  bool get isDownloaded => local.isDownloadingCompleted;
  bool get isUploading => remote.isUploadingActive;
  bool get isDownloading => local.isDownloadingActive;

  /// 0..1 of the active transfer, null when idle.
  double? get progress {
    final total = totalSize;
    if (total <= 0) return null;
    if (isUploading) return remote.uploadedSize / total;
    if (isDownloading) return local.downloadedSize / total;
    return null;
  }
}

/// Download/upload ring with a tap action (download, cancel), used on media
/// and documents. Shows the size when idle.
class TransferRing extends StatelessWidget {
  const TransferRing({super.key, required this.file, this.size = 46, this.idleIcon = Icons.download_rounded});

  final td.File file;
  final double size;
  final IconData idleIcon;

  @override
  Widget build(BuildContext context) {
    final store = context.read<FileStore>();
    return FileBuilder(
      file: file,
      builder: (context, f) {
        if (f.isDownloaded && !f.isUploading) return const SizedBox.shrink();
        final p = f.progress;
        final active = f.isDownloading || f.isUploading;
        return Semantics(
          button: true,
          label: active
              ? 'Cancel, ${((p ?? 0) * 100).round()} percent'
              : 'Download, ${Display.fileSize(f.totalSize)}',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: () => active ? store.cancel(f.id) : store.download(f.id, priority: 24),
            child: Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x99000000)),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (active)
                    SizedBox.square(
                      dimension: size - 6,
                      child: CircularProgressIndicator(value: p, strokeWidth: 2.6, color: GlowColors.cyan),
                    ),
                  Icon(active ? Icons.close_rounded : idleIcon, color: Colors.white, size: size * 0.45),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
