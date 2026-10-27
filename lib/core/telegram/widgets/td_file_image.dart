import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../file_store.dart';
import 'progressive_image.dart';

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
    this.fullResolution = false,
    this.progressive = false,
  });

  final td.File file;
  final Uint8List? placeholderBytes;
  final BoxFit fit;
  final int priority;
  final bool autoDownload;
  final String? semanticLabel;

  /// Decode every pixel (the zoomable viewer). Otherwise the image decodes
  /// at its laid-out size, which keeps big photos out of the image cache.
  final bool fullResolution;

  /// Photos: a gaussian-blurred minithumbnail that sharpens with the
  /// download (progressive JPEGs decode from their prefix), and the full
  /// image fades in over it.
  final bool progressive;

  @override
  State<TdFileImage> createState() => _TdFileImageState();
}

class _TdFileImageState extends State<TdFileImage> {
  late FileStore _files;
  Stream<td.File>? _stream;

  /// Progressive mode: the full image is on screen, the placeholder can go.
  var _fullShown = false;
  final _placeholderKey = GlobalKey();
  final _imageKey = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _files = context.read<FileStore>();
    _stream ??= _files.watch(widget.file.id);
    _files.remember(_files[widget.file.id] ?? widget.file, notify: false);
    _maybeDownload();
  }

  @override
  void didUpdateWidget(TdFileImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.id != widget.file.id) {
      _fullShown = false;
      _stream = _files.watch(widget.file.id);
      _maybeDownload();
    }
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
      stream: _stream,
      initialData: _files[widget.file.id] ?? widget.file,
      builder: (context, snapshot) {
        final f = snapshot.data!;
        final placeholder = widget.placeholderBytes != null
            ? Image.memory(
                widget.placeholderBytes!,
                fit: widget.fit,
                gaplessPlayback: true,
                // Upscaling the tiny minithumbnail smooths it; a blur layer
                // here cost a saveLayer and blur pass per tile per frame.
                filterQuality: FilterQuality.medium,
              )
            : const SizedBox.expand();
        final complete = f.local.isDownloadingCompleted && f.local.path.isNotEmpty;
        if (widget.progressive) return _progressive(f, complete);
        if (!complete) {
          return Semantics(label: widget.semanticLabel, image: true, child: placeholder);
        }
        Widget image(int? cacheWidth) => Image.file(
          File(f.local.path),
          fit: widget.fit,
          cacheWidth: cacheWidth,
          gaplessPlayback: true,
          semanticLabel: widget.semanticLabel,
          frameBuilder: (context, child, frame, sync) => sync || frame != null ? child : placeholder,
          errorBuilder: (_, _, _) => placeholder,
        );
        if (widget.fullResolution) return image(null);
        return _sized(image);
      },
    );
  }

  Widget _sized(Widget Function(int? cacheWidth) image) => LayoutBuilder(
    builder: (context, box) {
      final side = switch (widget.fit) {
        BoxFit.contain || BoxFit.fitWidth || BoxFit.scaleDown => box.maxWidth,
        _ when !box.maxHeight.isFinite => box.maxWidth,
        _ when !box.maxWidth.isFinite => box.maxHeight,
        _ => box.maxWidth > box.maxHeight ? box.maxWidth : box.maxHeight,
      };
      if (!side.isFinite) return image(null);
      return image((side * MediaQuery.devicePixelRatioOf(context)).round());
    },
  );

  /// Placeholder and image share one stack (keyed), so the sharpened
  /// placeholder stays put under the full image until it has faded in.
  Widget _progressive(td.File f, bool complete) {
    Widget image(int? cacheWidth) => Image.file(
      File(f.local.path),
      key: _imageKey,
      fit: widget.fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      semanticLabel: widget.semanticLabel,
      frameBuilder: (context, child, frame, sync) {
        if (sync || _fullShown) {
          if (!_fullShown) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _fullShown = true);
            });
          }
          return child;
        }
        if (frame == null) return const SizedBox.expand();
        return FadeInOnce(
          onDone: () {
            if (mounted) setState(() => _fullShown = true);
          },
          child: child,
        );
      },
      errorBuilder: (_, _, _) => const SizedBox.expand(),
    );
    return Semantics(
      label: widget.semanticLabel,
      image: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!_fullShown)
            ProgressivePlaceholder(
              key: _placeholderKey,
              file: f,
              minithumbnail: widget.placeholderBytes,
              fit: widget.fit,
            ),
          if (complete) widget.fullResolution ? image(null) : _sized(image),
        ],
      ),
    );
  }
}
