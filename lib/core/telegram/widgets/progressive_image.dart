import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:lumina_tdlib/api.dart' as td;

/// Progressive photo loading, Telegram-style: TDLib downloads a photo from
/// its first byte on (`downloadedPrefixSize`), and Telegram serves
/// progressive JPEGs, so decoding the prefix gives the whole picture at the
/// quality of the scans received so far. The codec does the sharpening;
/// nothing is invented. Baseline JPEGs (and other formats) can't decode
/// from a prefix and stay on the blurred thumbnail until complete.

/// Whether [head] (the file's first bytes) is a progressive JPEG; null while
/// too few bytes have arrived to tell.
bool? isProgressiveJpeg(Uint8List head) {
  if (head.length < 4) return null;
  if (head[0] != 0xFF || head[1] != 0xD8) return false;
  var i = 2;
  while (i + 4 <= head.length) {
    if (head[i] != 0xFF) return false;
    final marker = head[i + 1];
    if (marker == 0xFF) {
      i++;
      continue;
    }
    // Start of frame: C2 (and the rare C6/CA/CE) are progressive.
    if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
      return marker == 0xC2 || marker == 0xC6 || marker == 0xCA || marker == 0xCE;
    }
    if (marker == 0xDA) return false; // scan before any frame header
    final length = (head[i + 2] << 8) | head[i + 3];
    i += 2 + length;
  }
  return null;
}

/// When to decode the downloaded prefix again: decoding costs a codec pass,
/// so only on real progress and at most a few times a second.
class DecodePlan {
  const DecodePlan({this.first = 0.12, this.step = 0.10, this.interval = const Duration(milliseconds: 220)});

  /// Fraction before the first decode (the DC scan is in by then).
  final double first;

  /// New fraction needed between decodes.
  final double step;
  final Duration interval;

  bool due({required int prefix, required int total, required int lastPrefix, required Duration sinceLast}) {
    if (total <= 0 || prefix >= total) return false;
    final p = prefix / total;
    if (p < first) return false;
    if (lastPrefix == 0) return true;
    return (prefix - lastPrefix) / total >= step && sinceLast >= interval;
  }
}

/// Blur (logical px) laid over a prefix decode at [progress]: early scans
/// carry 8×8 block structure, which a soft blur turns into a smooth
/// picture; it fades to nothing as the scans fill in.
double blurFor(double progress) {
  final left = (1 - progress.clamp(0.0, 1.0));
  // Just enough to melt the blocks of the first scans; a stronger blur
  // threw away the detail they already carry.
  return 3.5 * left * left;
}

// ---- Widgets ------------------------------------------------------------------

/// Baked blurred minithumbnails, shared by every tile showing the same one.
final _blurred = <int, Future<ui.Image>>{};

Future<ui.Image> _bakeBlur(
  ui.Image src, {
  required int width,
  required int height,
  required double sigma,
  FilterQuality quality = FilterQuality.medium,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()
    ..filterQuality = quality
    ..imageFilter = sigma <= 0
        ? null
        : ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp);
  canvas.drawImageRect(
    src,
    Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    paint,
  );
  return recorder.endRecording().toImage(width, height);
}

Future<ui.Image> blurredMinithumbnail(Uint8List bytes) {
  final key = Object.hashAll(bytes);
  if (_blurred.length > 200) _blurred.remove(_blurred.keys.first);
  return _blurred[key] ??= () async {
    final codec = await ui.instantiateImageCodec(bytes);
    final src = (await codec.getNextFrame()).image;
    // Telegram-style: the ~40 px preview is enlarged with a smooth (bicubic)
    // filter in two 2× steps, then blurred only enough to hide its JPEG
    // blocks (about 0.7 source px; Telegram's stack blur is radius 3 at
    // this size). A wide gaussian over it left a single colour halo; this
    // keeps the shapes and colours readable until the photo arrives.
    final twice = await _bakeBlur(
      src,
      width: src.width * 2,
      height: src.height * 2,
      sigma: 0,
      quality: FilterQuality.high,
    );
    src.dispose();
    final image = await _bakeBlur(
      twice,
      width: twice.width * 2,
      height: twice.height * 2,
      sigma: 2.8,
      quality: FilterQuality.high,
    );
    twice.dispose();
    return image;
  }();
}

/// The not-yet-downloaded look: the minithumbnail as a soft gaussian blur,
/// then (progressive JPEGs) the downloaded prefix decoded at checkpoints,
/// each sharper one fading in over the last.
class ProgressivePlaceholder extends StatefulWidget {
  const ProgressivePlaceholder({
    super.key,
    required this.file,
    required this.minithumbnail,
    required this.fit,
  });

  final td.File file;
  final Uint8List? minithumbnail;
  final BoxFit fit;

  @override
  State<ProgressivePlaceholder> createState() => _ProgressivePlaceholderState();
}

class _ProgressivePlaceholderState extends State<ProgressivePlaceholder> {
  static const _plan = DecodePlan();

  ui.Image? _mini;
  ui.Image? _shown;
  ui.Image? _under;
  var _lastPrefix = 0;
  var _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool? _progressive;
  var _decoding = false;
  var _width = 0;

  @override
  void initState() {
    super.initState();
    final bytes = widget.minithumbnail;
    if (bytes != null) {
      blurredMinithumbnail(bytes).then((image) {
        if (mounted) setState(() => _mini = image);
      }, onError: (_) {});
    }
  }

  @override
  void didUpdateWidget(ProgressivePlaceholder old) {
    super.didUpdateWidget(old);
    _maybeDecode();
  }

  @override
  void dispose() {
    _shown?.dispose();
    _under?.dispose();
    super.dispose();
  }

  Future<void> _maybeDecode() async {
    final f = widget.file;
    final total = f.size > 0 ? f.size : f.expectedSize;
    final prefix = f.local.downloadedPrefixSize;
    if (_decoding || _progressive == false || _width == 0 || f.local.path.isEmpty) return;
    if (!_plan.due(
      prefix: prefix,
      total: total,
      lastPrefix: _lastPrefix,
      sinceLast: DateTime.now().difference(_lastAt),
    )) {
      return;
    }
    _decoding = true;
    try {
      final file = await File(f.local.path).open();
      final Uint8List bytes;
      try {
        bytes = await file.read(prefix);
      } finally {
        await file.close();
      }
      _progressive ??= isProgressiveJpeg(bytes);
      if (_progressive != true) return;
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: _width);
      final decoded = (await codec.getNextFrame()).image;
      final dpr = mounted ? MediaQuery.devicePixelRatioOf(context) : 1.0;
      final sigma = blurFor(prefix / total) * dpr;
      final baked = await _bakeBlur(decoded, width: decoded.width, height: decoded.height, sigma: sigma);
      decoded.dispose();
      _lastPrefix = prefix;
      _lastAt = DateTime.now();
      if (!mounted) {
        baked.dispose();
        return;
      }
      setState(() {
        _under?.dispose();
        _under = _shown;
        _shown = baked;
      });
    } catch (_) {
      // A prefix the codec can't read yet; the next checkpoint tries again.
    } finally {
      _decoding = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final side = box.maxWidth.isFinite ? box.maxWidth : (box.maxHeight.isFinite ? box.maxHeight : 640.0);
        final width = (side * MediaQuery.devicePixelRatioOf(context)).round().clamp(64, 2560);
        if (width != _width) {
          _width = width;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _maybeDecode();
          });
        }
        Widget raw(ui.Image image) => RawImage(
          image: image,
          fit: widget.fit,
          filterQuality: FilterQuality.medium,
          width: box.maxWidth,
          height: box.maxHeight,
        );
        final mini = widget.minithumbnail;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (_mini != null)
              raw(_mini!)
            else if (mini != null)
              Image.memory(mini, fit: widget.fit, gaplessPlayback: true, filterQuality: FilterQuality.medium),
            if (_under != null) raw(_under!),
            if (_shown != null) FadeInOnce(key: ObjectKey(_shown), child: raw(_shown!)),
          ],
        );
      },
    );
  }
}

/// Fades its child in once, then stays out of the way.
class FadeInOnce extends StatelessWidget {
  const FadeInOnce({super.key, required this.child, this.onDone});

  final Widget child;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOut,
    onEnd: onDone,
    builder: (context, t, child) => Opacity(opacity: t, child: child),
    child: child,
  );
}
