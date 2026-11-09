import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:path_provider/path_provider.dart';

import '../../media/ffmpeg_service.dart';
import '../display.dart';
import '../file_store.dart';
import 'file_progress.dart';
import 'looping_gif.dart';
import 'td_file_image.dart';

/// A GIF for a grid of many (the GIF picker), decoded in software like
/// Telegram does: no hardware video decoder per cell. Phones allow ~16 of
/// those for everything, so a grid of players stalled or took turns. Each
/// clip is converted once with FFmpeg to a small animated WebP (cell size,
/// 20 fps, cached on disk), which Flutter's image codec animates; as many
/// loop at once as are on screen. Falls back to [LoopingGif] if a
/// conversion fails.
class GifPreview extends StatelessWidget {
  const GifPreview({super.key, required this.file, this.thumbnail, this.minithumbnail, this.paused = false});

  final td.File file;
  final td.File? thumbnail;
  final td.Minithumbnail? minithumbnail;

  /// Held on its current frame (the grid is scrolling).
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final mini = Display.minithumbnail(minithumbnail);
    final Widget still = thumbnail != null
        ? TdFileImage(file: thumbnail!, placeholderBytes: mini)
        : mini != null
        ? Image.memory(mini, fit: BoxFit.cover)
        : const ColoredBox(color: Color(0xFF1A1D23));
    return FileBuilder(
      file: file,
      builder: (context, f) => f.isDownloaded && f.local.path.isNotEmpty
          ? _Converted(file: f, still: still, paused: paused, thumbnail: thumbnail, minithumbnail: minithumbnail)
          : _Fetch(file: f, child: still),
    );
  }
}

class _Fetch extends StatefulWidget {
  const _Fetch({required this.file, required this.child});

  final td.File file;
  final Widget child;

  @override
  State<_Fetch> createState() => _FetchState();
}

class _FetchState extends State<_Fetch> {
  @override
  void initState() {
    super.initState();
    final f = widget.file;
    if (f.local.canBeDownloaded && !f.local.isDownloadingActive) {
      context.read<FileStore>().download(f.id, priority: 4).ignore();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Converted extends StatefulWidget {
  const _Converted({
    required this.file,
    required this.still,
    required this.paused,
    this.thumbnail,
    this.minithumbnail,
  });

  final td.File file;
  final Widget still;
  final bool paused;
  final td.File? thumbnail;
  final td.Minithumbnail? minithumbnail;

  @override
  State<_Converted> createState() => _ConvertedState();
}

class _ConvertedState extends State<_Converted> {
  String? _webp;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    GifPreviews.of(context.read<FfmpegService>())
        .preview(widget.file)
        .then((path) {
          if (!mounted) return;
          setState(() => path == null ? _failed = true : _webp = path);
        })
        .ignore();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return LoopingGif(
        file: widget.file,
        thumbnail: widget.thumbnail,
        minithumbnail: widget.minithumbnail,
        paused: widget.paused,
      );
    }
    final webp = _webp;
    if (webp == null) return widget.still;
    // TickerMode holds an animated image on its frame.
    return TickerMode(
      enabled: !widget.paused,
      child: Image.file(
        File(webp),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        frameBuilder: (context, child, frame, _) => frame == null ? widget.still : child,
      ),
    );
  }
}

/// Converted previews on disk, at most two FFmpeg runs at a time (newest
/// requests first: they are what's on screen).
class GifPreviews {
  GifPreviews._(this._ffmpeg);

  static GifPreviews? _instance;
  static GifPreviews of(FfmpegService ffmpeg) => _instance ??= GifPreviews._(ffmpeg);

  final FfmpegService _ffmpeg;
  final _done = <String, Future<String?>>{};
  final _queue = Queue<void Function()>();
  var _running = 0;
  static const _parallel = 2;

  Future<String?> preview(td.File file) {
    final key = file.remote.uniqueId.isNotEmpty ? file.remote.uniqueId : 'id${file.id}_${file.size}';
    return _done[key] ??= _make(key, file.local.path).then((path) {
      // A failure may be passing (no space): try again next time.
      if (path == null) _done.remove(key);
      return path;
    });
  }

  Future<String?> _make(String key, String source) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/gif_previews');
    final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final out = File('${dir.path}/$safe.webp');
    if (out.existsSync() && out.lengthSync() > 0) return out.path;
    await dir.create(recursive: true);
    final slot = Completer<void>();
    _queue.addFirst(slot.complete);
    _pump();
    await slot.future;
    try {
      final tmp = '${out.path}.part.webp';
      final ok = await _ffmpeg.run([
        '-t', '15', //
        '-i', source,
        '-an',
        '-vf', 'fps=20,scale=240:-2:flags=bilinear',
        '-c:v', 'libwebp',
        '-lossless', '0',
        '-q:v', '62',
        '-compression_level', '2',
        '-loop', '0',
        tmp,
      ]);
      if (!ok || !File(tmp).existsSync()) return null;
      await File(tmp).rename(out.path);
      return out.path;
    } catch (_) {
      return null;
    } finally {
      _running--;
      _pump();
    }
  }

  void _pump() {
    while (_running < _parallel && _queue.isNotEmpty) {
      _running++;
      _queue.removeFirst()();
    }
  }
}
