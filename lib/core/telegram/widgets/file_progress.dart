import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../theme/glow_colors.dart';
import '../display.dart';
import '../file_store.dart';

/// Rebuilds with the latest state of a TDLib file.
class FileBuilder extends StatefulWidget {
  const FileBuilder({super.key, required this.file, required this.builder});

  final td.File file;
  final Widget Function(BuildContext context, td.File file) builder;

  @override
  State<FileBuilder> createState() => _FileBuilderState();
}

class _FileBuilderState extends State<FileBuilder> {
  late final FileStore _store = context.read<FileStore>();
  // Made once: watch() is an async* generator, so a new stream per build
  // meant a resubscribe and an extra rebuild each time.
  late Stream<td.File> _stream = _store.watch(widget.file.id);

  @override
  void didUpdateWidget(FileBuilder old) {
    super.didUpdateWidget(old);
    if (old.file.id != widget.file.id) _stream = _store.watch(widget.file.id);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<td.File>(
    stream: _stream,
    initialData: _store[widget.file.id] ?? widget.file,
    builder: (context, snap) => widget.builder(context, snap.data!),
  );
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
  const TransferRing({
    super.key,
    required this.file,
    this.size = 46,
    this.idleIcon = Icons.download_rounded,
    this.onStart,
  });

  final td.File file;
  final double size;
  final IconData idleIcon;

  /// Called when a tap starts a download (the Downloads list records it).
  final ValueChanged<td.File>? onStart;

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
            onTap: () {
              if (active) {
                store.cancel(f.id);
              } else {
                store.download(f.id, priority: 24);
                onStart?.call(f);
              }
            },
            child: Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x99000000)),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Unknown size: no indeterminate ring, which would redraw forever.
                  if (active && p != null)
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
