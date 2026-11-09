import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart';

import 'animated_sticker.dart' show decodeTgs;

/// Pre-drawn frames of one looping TGS animation at one pixel size, shared by
/// every widget showing it.
///
/// Drawing Lottie vectors live per emoji per frame (what `Lottie.file` does)
/// collapses with a few dozen animated custom emoji on screen. Telegram's
/// answer, used here too: render each animation once into images at the size
/// shown, then every copy just blits the current frame. Frames are drawn a
/// few per vsync so building the strip never stalls scrolling.
class LottieFrames {
  LottieFrames._(this.key, this.fps);

  final String key;
  final double fps;
  final List<ui.Image> frames = [];
  int total = 0;
  bool get complete => total > 0 && frames.length == total;
  bool failed = false;
  final _listeners = <VoidCallback>[];

  /// Frames at most this rate (24 fps reads as smooth for emoji, a third of
  /// the memory of 60).
  static const maxFps = 24.0;

  /// LRU cache: (file, size) → frames. ~60 KB per frame at 48 px … capped.
  static final _cache = LinkedHashMap<String, LottieFrames>();
  static const _maxEntries = 48;

  static LottieFrames obtain(String path, int px) {
    final key = '$path@$px';
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // most recent last
      return hit;
    }
    final f = LottieFrames._(key, maxFps);
    _cache[key] = f;
    while (_cache.length > _maxEntries) {
      final old = _cache.remove(_cache.keys.first)!;
      old._dispose();
    }
    f._build(path, px);
    return f;
  }

  static final _compositions = <String, Future<LottieComposition?>>{};

  Future<void> _build(String path, int px) async {
    try {
      final composition = await (_compositions[path] ??= File(path).readAsBytes().then(decodeTgs));
      if (composition == null) {
        failed = true;
        _notify();
        return;
      }
      final seconds = composition.seconds.clamp(0.1, 6.0);
      total = math.max(1, (seconds * fps).round());
      final drawable = LottieDrawable(composition);
      final rect = Rect.fromLTWH(0, 0, px.toDouble(), px.toDouble());
      // A few frames per vsync, at idle priority.
      var i = 0;
      while (i < total && !_disposed) {
        await SchedulerBinding.instance.scheduleTask(() {
          for (var n = 0; n < 4 && i < total && !_disposed; n++, i++) {
            drawable.setProgress(i / total);
            final recorder = ui.PictureRecorder();
            drawable.draw(Canvas(recorder), rect, fit: BoxFit.contain);
            final picture = recorder.endRecording();
            frames.add(picture.toImageSync(px, px));
            picture.dispose();
          }
        }, Priority.animation);
        if (frames.length == 1 || frames.length == total) _notify();
      }
    } catch (_) {
      failed = true;
      _notify();
    }
  }

  void addListener(VoidCallback l) => _listeners.add(l);
  void removeListener(VoidCallback l) => _listeners.remove(l);
  void _notify() {
    for (final l in [..._listeners]) {
      l();
    }
  }

  bool _disposed = false;
  void _dispose() {
    _disposed = true;
    for (final f in frames) {
      f.dispose();
    }
    frames.clear();
  }

  /// The frame to show at [elapsed]; while frames are still being drawn,
  /// the newest one ready.
  ui.Image? frameAt(Duration elapsed) {
    if (frames.isEmpty) return null;
    if (!complete) return frames.last;
    final i = (elapsed.inMicroseconds * fps / 1e6).floor() % total;
    return frames[i];
  }
}

/// One clock for every cached animation on screen: a single ticker that runs
/// only while at least one is visible.
class _SharedClock extends ChangeNotifier {
  _SharedClock._();
  static final instance = _SharedClock._();

  Ticker? _ticker;
  Duration elapsed = Duration.zero;
  int _users = 0;
  Duration _lastFrame = Duration.zero;

  void attach() {
    _users++;
    _ticker ??= Ticker((t) {
      // Notify at the frame rate, not the display rate (60–120 Hz).
      if ((t - _lastFrame).inMicroseconds >= 1e6 / LottieFrames.maxFps - 2000) {
        _lastFrame = t;
        elapsed = t;
        notifyListeners();
      }
    });
    if (!_ticker!.isActive) _ticker!.start();
  }

  void detach() {
    _users--;
    if (_users <= 0) {
      _users = 0;
      _ticker?.stop();
      _lastFrame = Duration.zero;
    }
  }
}

/// A looping TGS animation drawn from [LottieFrames]: the cheap way to show
/// many animated emoji at once. [placeholder] shows until the first frame.
class CachedLottie extends StatefulWidget {
  const CachedLottie({super.key, required this.path, required this.size, required this.placeholder});

  final String path;
  final double size;
  final Widget placeholder;

  @override
  State<CachedLottie> createState() => _CachedLottieState();
}

class _CachedLottieState extends State<CachedLottie> {
  LottieFrames? _frames;
  ValueListenable<bool>? _tickerMode;
  var _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final px = (widget.size * MediaQuery.devicePixelRatioOf(context)).round().clamp(16, 256);
    final next = LottieFrames.obtain(widget.path, px);
    if (!identical(next, _frames)) {
      _frames?.removeListener(_changed);
      _frames = next..addListener(_changed);
    }
    final mode = TickerMode.getNotifier(context);
    if (!identical(mode, _tickerMode)) {
      _tickerMode?.removeListener(_syncClock);
      _tickerMode = mode..addListener(_syncClock);
    }
    _syncClock();
  }

  @override
  void didUpdateWidget(CachedLottie old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.size != widget.size) didChangeDependencies();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Joins the shared clock only while visible (another tab or route pauses it).
  void _syncClock() {
    final run = _tickerMode?.value ?? true;
    if (run && !_running) {
      _running = true;
      _SharedClock.instance.attach();
    } else if (!run && _running) {
      _running = false;
      _SharedClock.instance.detach();
    }
  }

  @override
  void dispose() {
    _frames?.removeListener(_changed);
    _tickerMode?.removeListener(_syncClock);
    if (_running) _SharedClock.instance.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frames = _frames;
    if (frames == null || frames.failed || frames.frames.isEmpty) {
      return SizedBox.square(dimension: widget.size, child: widget.placeholder);
    }
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _FramePainter(frames, _SharedClock.instance),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.frames, this.clock) : super(repaint: clock);

  final LottieFrames frames;
  final _SharedClock clock;

  @override
  void paint(Canvas canvas, Size size) {
    final image = frames.frameAt(clock.elapsed);
    if (image == null) return;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => !identical(old.frames, frames);
}
