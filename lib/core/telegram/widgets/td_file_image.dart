import 'dart:ui' show ImageFilter;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../file_store.dart';

/// Image backed by a TDLib file: shows [placeholder] (usually the blurred
/// minithumbnail) and swaps to the real image once TDLib has it locally.
/// Downloads start when the widget is first built.
class TdFileImage extends StatefulWidget {
  const TdFileImage({
    super.key,
    required this.file,
    this.placeholderBytes,
    this.fit = BoxFit.cover,
    this.priority = 8,
    this.autoDownload = true,
    this.semanticLabel,
  });

  final td.File file;
  final Uint8List? placeholderBytes;
  final BoxFit fit;
  final int priority;
  final bool autoDownload;
  final String? semanticLabel;

  @override
  State<TdFileImage> createState() => _TdFileImageState();
}

class _TdFileImageState extends State<TdFileImage> {
  late FileStore _files;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _files = context.read<FileStore>();
    _files.remember(_files[widget.file.id] ?? widget.file);
    _maybeDownload();
  }

  @override
  void didUpdateWidget(TdFileImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.id != widget.file.id) _maybeDownload();
  }

  void _maybeDownload() {
    final f = _files[widget.file.id] ?? widget.file;
    if (widget.autoDownload &&
        !f.local.isDownloadingCompleted &&
        f.local.canBeDownloaded &&
        !f.local.isDownloadingActive) {
      _files.download(f.id, priority: widget.priority).ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<td.File>(
      stream: _files.watch(widget.file.id),
      initialData: _files[widget.file.id] ?? widget.file,
      builder: (context, snapshot) {
        final f = snapshot.data!;
        final placeholder = widget.placeholderBytes != null
            ? Image.memory(
                widget.placeholderBytes!,
                fit: widget.fit,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
              )
            : const SizedBox.expand();
        if (!f.local.isDownloadingCompleted || f.local.path.isEmpty) {
          return Semantics(
            label: widget.semanticLabel,
            image: true,
            child: ImageFiltered(imageFilter: _blur, child: placeholder),
          );
        }
        return Image.file(
          File(f.local.path),
          fit: widget.fit,
          gaplessPlayback: true,
          semanticLabel: widget.semanticLabel,
          frameBuilder: (context, child, frame, sync) => sync || frame != null ? child : placeholder,
          errorBuilder: (_, _, _) => placeholder,
        );
      },
    );
  }
}

final _blur = ImageFilter.blur(sigmaX: 6, sigmaY: 6);
