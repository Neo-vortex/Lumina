import '../../widgets/chat_scrolling.dart';
import 'progressive_image.dart';

import 'dart:async';
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
  VideoPlayerController? _player;
  VideoPlayerController get _c => _player!;
  var _ready = false;
  _GifPool? _pool;

  // New video frames don't schedule a Flutter frame on their own here
  // (Impeller + SurfaceProducer): with nothing else animating, the clip
  // froze after a few frames while the decoder kept going. A ticker keeps
  // frames coming while this GIF is on screen, and only then.
  late final Ticker _frames = createTicker((_) {});

  /// Started only once the reader settles here: flinging past a GIF never
  /// opens a decoder. While the list moves it holds its frame.
  Timer? _dwell;
  var _begun = false;

  @override
  void initState() {
    super.initState();
    _pool = GifBudget._of(context);
    ChatScrolling.moving.addListener(_onScroll);
    _onScroll();
  }

  void _onScroll() {
    _dwell?.cancel();
    if (ChatScrolling.moving.value) {
      if (_ready && _player != null) _applyPaused();
      return;
    }
    _dwell = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (!_begun) {
        _begun = true;
        final pool = _pool;
        if (pool == null) {
          _start();
        } else {
          pool.acquire(this);
        }
      } else if (_ready && _player != null) {
        _applyPaused();
      }
    });
  }

  // Watchdog: a hardware decoder the phone refused (too many open) shows a
  // few frames and then the position stops moving. Rebuild that player.
  Timer? _watch;
  Duration _lastPos = Duration.zero;
  var _stuck = 0, _restarts = 0;

  void _check() {
    final p = _player;
    if (p == null || !_ready || widget.paused || !mounted) return;
    final pos = p.value.position;
    if (pos != _lastPos) {
      _lastPos = pos;
      _stuck = 0;
      return;
    }
    // ~2 s without progress; a few retries at most, then rest on the still.
    if (++_stuck < 2 || _restarts >= 4) return;
    _restarts++;
    _stuck = 0;
    final old = p;
    setState(() {
      _player = null;
      _ready = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
      // Give the decoder back before asking for a new one.
      Future.delayed(Duration(milliseconds: 300 * _restarts), _start);
    });
  }

  /// Gives the decoder back (the pool rotates slots): the still shows until
  /// this GIF's next turn.
  void _suspend() {
    final p = _player;
    if (p == null || !mounted) return;
    if (_frames.isActive) _frames.stop();
    setState(() {
      _player = null;
      _ready = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => p.dispose());
  }

  /// A decoder slot is ours (or there is no budget): make the player.
  void _start() {
    if (!mounted || _player != null) return;
    _watch ??= Timer.periodic(const Duration(seconds: 1), (_) => _check());
    _lastPos = Duration.zero;
    _player = widget.player(File(widget.path));
    _frames.start();
    _c
      ..setLooping(true)
      ..setVolume(0);
    _c
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => _ready = true);
          // Whatever happened while initializing, follow the latest state.
          _applyPaused();
        })
        .catchError((Object _) {});
    setState(() {});
  }

  @override
  void didUpdateWidget(_Playing old) {
    super.didUpdateWidget(old);
    // Before the player is ready, initialize() applies the current state.
    if (old.paused == widget.paused || !_ready || _player == null) return;
    _applyPaused();
  }

  void _applyPaused() {
    if (widget.paused || ChatScrolling.moving.value) {
      _c.pause();
      if (_frames.isActive) _frames.stop();
    } else {
      _c.play();
      if (!_frames.isActive) _frames.start();
    }
  }

  @override
  void dispose() {
    _dwell?.cancel();
    ChatScrolling.moving.removeListener(_onScroll);
    _watch?.cancel();
    _frames.dispose();
    _player?.dispose();
    _pool?.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.still,
      // The moving picture fades in over the still, fast.
      if (_ready && _player != null)
        FadeInOnce(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(width: _c.value.size.width, height: _c.value.size.height, child: VideoPlayer(_c)),
          ),
        ),
    ],
  );
}

/// Caps how many GIFs decode at once below it. Each loop is a hardware
/// decoder, and phones allow only so many: past that, players start, show a
/// few frames and stall. GIFs over the cap show their still and start as
/// soon as a slot frees. The chat needs no budget (a few GIFs on screen);
/// the GIF panel's grid does.
class GifBudget extends StatefulWidget {
  const GifBudget({super.key, required this.max, required this.child});

  final int max;
  final Widget child;

  static _GifPool? _of(BuildContext context) => context.getInheritedWidgetOfExactType<_GifScope>()?.pool;

  @override
  State<GifBudget> createState() => _GifBudgetState();
}

class _GifBudgetState extends State<GifBudget> {
  late final _pool = _GifPool(widget.max);

  @override
  void dispose() {
    _pool.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _GifScope(pool: _pool, child: widget.child);
}

class _GifScope extends InheritedWidget {
  const _GifScope({required this.pool, required super.child});

  final _GifPool pool;

  @override
  bool updateShouldNotify(_GifScope old) => false;
}

class _GifPool {
  _GifPool(this.max);

  final int max;

  /// Playing, oldest first.
  final _live = <_PlayingState>[];
  final _waiting = <_PlayingState>[];
  Timer? _rotate;

  /// Phones allow so many hardware decoders (16 here, shared with every
  /// other video): when more GIFs are on screen than slots, they take turns
  /// instead of the extra ones sitting still for good.
  static const _turn = Duration(seconds: 4);

  void acquire(_PlayingState gif) {
    if (_live.length < max) {
      _live.add(gif);
      gif._start();
    } else {
      _waiting.add(gif);
      _rotate ??= Timer.periodic(_turn, (_) => _next());
    }
  }

  void _next() {
    _waiting.removeWhere((g) => !g.mounted);
    if (_waiting.isEmpty || _live.isEmpty) {
      _rotate?.cancel();
      _rotate = null;
      return;
    }
    final done = _live.removeAt(0);
    done._suspend();
    _waiting.add(done);
    final next = _waiting.removeAt(0);
    _live.add(next);
    // After the old player's decoder is released.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 60), () {
        if (next.mounted && _live.contains(next)) next._start();
      });
    });
  }

  void dispose() {
    _rotate?.cancel();
    _rotate = null;
  }

  void release(_PlayingState gif) {
    _waiting.remove(gif);
    if (!_live.remove(gif)) return;
    while (_waiting.isNotEmpty && _live.length < max) {
      final next = _waiting.removeAt(0);
      if (!next.mounted) continue;
      _live.add(next);
      // Not during the releasing widget's teardown.
      WidgetsBinding.instance.addPostFrameCallback((_) => next._start());
    }
    if (_waiting.isEmpty) {
      _rotate?.cancel();
      _rotate = null;
    }
  }
}
