import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:video_player/video_player.dart';

import '../display.dart';
import '../file_store.dart';
import 'file_progress.dart';
import 'td_file_image.dart';

/// Makes the player for a downloaded GIF (swapped in tests).
typedef GifPlayerFactory = VideoPlayerController Function(File file);

/// A Telegram GIF (an MP4) looping silently, like Telegram: the thumbnail
/// first, then the clip once its (small) file is downloaded. Uses ExoPlayer
/// through video_player, far lighter than a VLC instance per cell; the
/// player lives only while the widget is on screen.
class LoopingGif extends StatelessWidget {
  const LoopingGif({
    super.key,
    required this.file,
    this.thumbnail,
    this.minithumbnail,
    this.player,
    this.paused = false,
    this.autoDownload = true,
  });

  final td.File file;
  final td.File? thumbnail;
  final td.Minithumbnail? minithumbnail;
  final GifPlayerFactory? player;

  /// Held still (tapped to pause in chat).
  final bool paused;

  /// Download the clip on sight; off, it waits for the transfer ring.
  final bool autoDownload;

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
          ? _Playing(
              path: f.local.path,
              still: still,
              player: player ?? VideoPlayerController.file,
              paused: paused,
            )
          : autoDownload
          ? _Fetch(file: f, child: still)
          : still,
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

class _Playing extends StatefulWidget {
  const _Playing({required this.path, required this.still, required this.player, required this.paused});

  final String path;
  final Widget still;
  final GifPlayerFactory player;
  final bool paused;

  @override
  State<_Playing> createState() => _PlayingState();
}

class _PlayingState extends State<_Playing> with SingleTickerProviderStateMixin {
  late final VideoPlayerController _c = widget.player(File(widget.path));
  var _ready = false;

  // New video frames don't schedule a Flutter frame on their own here
  // (Impeller + SurfaceProducer): with nothing else animating, the clip
  // froze after a few frames while the decoder kept going. A ticker keeps
  // frames coming while this GIF is on screen, and only then.
  late final Ticker _frames = createTicker((_) {});

  @override
  void initState() {
    super.initState();
    _frames.start();
    _c
      ..setLooping(true)
      ..setVolume(0);
    _c
        .initialize()
        .then((_) {
          if (!mounted) return;
          if (!widget.paused) _c.play();
          setState(() => _ready = true);
        })
        .catchError((Object _) {});
  }

  @override
  void didUpdateWidget(_Playing old) {
    super.didUpdateWidget(old);
    if (old.paused == widget.paused || !_ready) return;
    if (widget.paused) {
      _c.pause();
      _frames.stop();
    } else {
      _c.play();
      _frames.start();
    }
  }

  @override
  void dispose() {
    _frames.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.still,
      if (_ready)
        FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(width: _c.value.size.width, height: _c.value.size.height, child: VideoPlayer(_c)),
        ),
    ],
  );
}
