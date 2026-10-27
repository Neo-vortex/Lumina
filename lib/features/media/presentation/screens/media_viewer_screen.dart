import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/media/tdlib_stream_server.dart';
import '../../../../core/storage/app_preferences.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/file_store.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/formatted_text_view.dart';
import '../../../../core/telegram/widgets/td_file_image.dart';
import '../widgets/media_flight.dart';
import '../widgets/media_geometry.dart';
import '../widgets/video_player_view.dart';

/// Biggest photo size (what the viewer shows).
td.PhotoSize? largestSize(td.Photo photo) => photo.sizes.isEmpty
    ? null
    : photo.sizes.reduce((a, b) => a.width * a.height >= b.width * b.height ? a : b);

/// Full-screen gallery over photos and videos (spec §9.2 media cluster).
///
/// One gesture engine drives everything, Telegram-style: pictures fly out of
/// their chat tile and back into it (the crop morphs, the tile steps aside),
/// a drag follows the finger 1:1 and scales the picture down while the chat
/// shows through, pinch zooms about the fingers with rubber-banded limits,
/// and paging springs with the flick. Every animation can be grabbed
/// mid-way and continues from where it is.
class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({super.key, required this.messages, required this.initialIndex, this.onOpened});

  final List<td.Message> messages;
  final int initialIndex;

  /// View-once / self-destructing content must be marked opened.
  final void Function(td.Message message)? onOpened;

  static Future<void> open(
    BuildContext context,
    List<td.Message> messages, {
    int index = 0,
    void Function(td.Message)? onOpened,
  }) async {
    final navigator = Navigator.of(context);
    // Decode the picture the flight starts with before the first frame, so
    // it never begins on the blurred placeholder.
    await _precache(context, messages[index]);
    await navigator.push(
      PageRouteBuilder<void>(
        opaque: false,
        // The viewer draws its own backdrop and flights.
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) =>
            MediaViewerScreen(messages: messages, initialIndex: index, onOpened: onOpened),
      ),
    );
  }

  static Future<void> _precache(BuildContext context, td.Message m) async {
    final FileStore files;
    try {
      files = context.read<FileStore>();
    } on ProviderNotFoundException {
      return;
    }
    final pictures = _Pictures.of(m);
    if (pictures == null) return;
    final jobs = <Future<void>>[
      for (final f in [pictures.thumb, pictures.full])
        if (f != null)
          if ((files[f.id] ?? f).local case final l when l.isDownloadingCompleted && l.path.isNotEmpty)
            precacheImage(FileImage(File(l.path)), context),
    ];
    if (jobs.isEmpty) return;
    await Future.wait(jobs).timeout(const Duration(milliseconds: 150), onTimeout: () => const []);
  }

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

enum _Mode { none, pinch, pan, page, dismiss }

class _MediaViewerScreenState extends State<MediaViewerScreen> with TickerProviderStateMixin {
  static const _maxZoom = 5.0;
  static const _spring = SpringDescription(mass: 1, stiffness: 520, damping: 46);

  late double _pos = widget.initialIndex.toDouble();
  late int _index = widget.initialIndex;
  var _chrome = true;
  var _zoom = Zoom.identity;
  var _drag = Offset.zero;
  var _size = Size.zero;

  // Gesture start state.
  var _mode = _Mode.none;
  var _startZoom = Zoom.identity;
  var _startFocal = Offset.zero;
  var _startPos = 0.0;
  var _startDrag = Offset.zero;
  var _doubleTapAt = Offset.zero;
  // Pinch runs frame to frame, so a finger joining or leaving re-anchors it.
  var _lastFocal = Offset.zero;
  var _lastScale = 1.0;
  var _rawScale = 1.0;

  late final _pageCtl = AnimationController.unbounded(vsync: this)..addListener(_onPageTick);
  late final _dragCtl = AnimationController(vsync: this)..addListener(_onDragTick);
  late final _zoomCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300))
    ..addListener(_onZoomTick);
  late final _flightCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  Offset _dragFrom = Offset.zero;
  Zoom _zoomFrom = Zoom.identity, _zoomTo = Zoom.identity;

  // Flights: open from the tile, close back into it (or fade when the tile
  // is off screen).
  Rect? _openFrom;
  var _closing = false;
  var _closed = false;
  ({Rect clip, Rect image})? _closeFrom;
  Rect? _closeTo;
  var _closeBackdrop = 1.0;

  td.Message get _message => widget.messages[_index];

  @override
  void initState() {
    super.initState();
    _markOpened(_message);
    _openFrom = MediaFlight.rectOf(_message.id);
    MediaFlight.hidden.value = _message.id;
    _flightCtl.addListener(() => setState(() {}));
    _flightCtl.forward().whenComplete(() {
      if (!_closing && MediaFlight.hidden.value == _message.id) MediaFlight.hidden.value = null;
    });
  }

  void _markOpened(td.Message m) {
    if (m.selfDestructType != null) widget.onOpened?.call(m);
  }

  @override
  void dispose() {
    if (MediaFlight.hidden.value != null && widget.messages.any((m) => m.id == MediaFlight.hidden.value)) {
      MediaFlight.hidden.value = null;
    }
    _pageCtl.dispose();
    _dragCtl.dispose();
    _zoomCtl.dispose();
    _flightCtl.dispose();
    super.dispose();
  }

  // ---- Animation ticks -----------------------------------------------------

  void _onPageTick() {
    _pos = _pageCtl.value;
    _syncIndex();
    setState(() {});
  }

  void _onDragTick() => setState(() => _drag = _dragFrom * (1 - _dragCtl.value));

  void _onZoomTick() =>
      setState(() => _zoom = Zoom.lerp(_zoomFrom, _zoomTo, Curves.easeOutCubic.transform(_zoomCtl.value)));

  void _syncIndex() {
    final i = _pos.round().clamp(0, widget.messages.length - 1);
    if (i == _index) return;
    _index = i;
    _zoom = Zoom.identity;
    _markOpened(_message);
  }

  void _stopAll() {
    _pageCtl.stop();
    _dragCtl.stop();
    _zoomCtl.stop();
  }

  void _animateZoom(Zoom to) {
    _zoomFrom = _zoom;
    _zoomTo = to;
    _zoomCtl.forward(from: 0);
  }

  // ---- Geometry --------------------------------------------------------------

  Rect _contentRect(td.Message m) => containRect(_Pictures.of(m)?.aspect ?? 16 / 9, Offset.zero & _size);

  double get _dismissProgress => (_drag.dy.abs() / (_size.height * 0.5)).clamp(0.0, 1.0);

  double get _dragScale => 1 - 0.3 * _dismissProgress;

  /// Where the current picture is drawn right now (zoom, then drag).
  Rect _shownRect(td.Message m) {
    final r = _zoom.applyRect(_contentRect(m));
    final c = r.center + _drag;
    return Rect.fromCenter(center: c, width: r.width * _dragScale, height: r.height * _dragScale);
  }

  // ---- Close -----------------------------------------------------------------

  void _close() {
    if (_closing) return;
    _stopAll();
    final m = _message;
    final pictures = _Pictures.of(m);
    final shown = _shownRect(m);
    var to = MediaFlight.rectOf(m.id);
    if (to != null && !(Offset.zero & _size).overlaps(to)) to = null;
    setState(() {
      _closing = true;
      _chrome = false;
      _closeFrom = (clip: shown.intersect(Offset.zero & _size), image: shown);
      _closeTo = pictures == null ? null : to;
      _closeBackdrop = _backdropOpacity;
    });
    MediaFlight.hidden.value = m.id;
    _flightCtl.duration = const Duration(milliseconds: 260);
    _flightCtl.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      MediaFlight.hidden.value = null;
      setState(() => _closed = true);
      Navigator.of(context).pop();
    });
  }

  double get _backdropOpacity {
    if (_closing) return _closeBackdrop * (1 - Curves.easeOut.transform(_flightCtl.value));
    final open = Curves.easeOut.transform(_flightCtl.value);
    return open * (1 - _dismissProgress);
  }

  // ---- Gestures ----------------------------------------------------------------

  bool get _isVideoPage => _message.content is! td.MessagePhoto;

  /// Which recognizers run; follows the page only once a swipe settles, as
  /// swapping them mid-swipe would drop the gesture.
  late bool _videoGestures = _isVideoPage;

  void _settleGestures() {
    if (_videoGestures != _isVideoPage && mounted) setState(() => _videoGestures = _isVideoPage);
  }

  void _onStart(Offset focal) {
    if (_closing) return;
    _stopAll();
    _mode = _Mode.none;
    _startZoom = _zoom;
    _startFocal = focal;
    _startPos = _pos;
    _startDrag = _drag;
    _lastFocal = focal;
    _lastScale = 1;
    _rawScale = _zoom.scale;
  }

  void _onUpdate(Offset focal, double scale, int pointers) {
    if (_closing) return;
    if (pointers >= 2 &&
        !_isVideoPage &&
        (_mode == _Mode.none || _mode == _Mode.pan || _mode == _Mode.pinch)) {
      _mode = _Mode.pinch;
      _rawScale *= scale / _lastScale;
      final banded = rubberBand(_rawScale, min: 1, max: _maxZoom);
      setState(
        () => _zoom = _zoom.pinch(
          start: _zoom,
          startFocal: _lastFocal,
          focal: focal,
          scale: banded / _zoom.scale,
        ),
      );
      _lastFocal = focal;
      _lastScale = scale;
      return;
    }
    final delta = focal - _startFocal;
    if (_mode == _Mode.none) {
      if (_startZoom.zoomed && !_isVideoPage) {
        _mode = _Mode.pan;
      } else if (delta.distance > 2) {
        _mode = delta.dx.abs() > delta.dy.abs() && widget.messages.length > 1 ? _Mode.page : _Mode.dismiss;
        if (_mode == _Mode.dismiss) {
          MediaFlight.hidden.value = _message.id;
          setState(() => _chrome = false);
        }
      } else {
        return;
      }
    }
    switch (_mode) {
      case _Mode.pan:
        final raw = Zoom(scale: _startZoom.scale, offset: _startZoom.offset + delta);
        final bound = raw.settled(_contentRect(_message), _size, max: _maxZoom);
        setState(
          () => _zoom = Zoom(scale: raw.scale, offset: bound.offset + (raw.offset - bound.offset) * 0.35),
        );
      case _Mode.page:
        var p = _startPos - delta.dx / _size.width;
        final last = (widget.messages.length - 1).toDouble();
        if (p < 0) p = p / 3;
        if (p > last) p = last + (p - last) / 3;
        _pos = p;
        _syncIndex();
        setState(() {});
      case _Mode.dismiss:
        setState(() => _drag = _startDrag + delta);
      case _Mode.pinch || _Mode.none:
        break;
    }
  }

  void _onEnd(Velocity velocity, int pointersLeft) {
    if (_closing || pointersLeft > 0) return;
    final v = velocity.pixelsPerSecond;
    switch (_mode) {
      case _Mode.pinch || _Mode.pan:
        // A little fling carries the pan, then it settles inside the bounds.
        final flung = Zoom(scale: _zoom.scale, offset: _zoom.offset + v * 0.12);
        _animateZoom(flung.settled(_contentRect(_message), _size, max: _maxZoom));
      case _Mode.page:
        final target = settlePage(position: _pos, velocity: -v.dx, count: widget.messages.length);
        _pageCtl.value = _pos;
        _pageCtl
            .animateWith(SpringSimulation(_spring, _pos, target.toDouble(), -v.dx / _size.width))
            .whenComplete(_settleGestures);
      case _Mode.dismiss:
        if (shouldDismiss(offset: _drag.dy, velocity: v.dy, height: _size.height)) {
          _close();
        } else {
          _dragFrom = _drag;
          _dragCtl.value = 0;
          _dragCtl.animateWith(SpringSimulation(_spring, 0, 1, 0)).whenComplete(() {
            if (!_closing && _drag == Offset.zero) {
              MediaFlight.hidden.value = null;
              setState(() => _chrome = true);
            }
          });
        }
      case _Mode.none:
        break;
    }
    _mode = _Mode.none;
  }

  void _onDoubleTap() {
    if (_closing || _isVideoPage) return;
    _stopAll();
    final target = _zoom.zoomed
        ? Zoom.identity
        : Zoom(
            scale: 2.5,
            offset: _doubleTapAt * (1 - 2.5),
          ).settled(_contentRect(_message), _size, max: _maxZoom);
    _animateZoom(target);
  }

  Map<Type, GestureRecognizerFactory> get _gestures {
    if (_videoGestures) {
      // The player handles taps; plain drags (a smaller slop than its own
      // gestures) page and dismiss.
      void start(DragStartDetails d) => _onStart(d.localPosition);
      void update(DragUpdateDetails d) => _onUpdate(d.localPosition, 1, 1);
      void end(DragEndDetails d) => _onEnd(d.velocity, 0);
      return {
        HorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
              HorizontalDragGestureRecognizer.new,
              (r) => r
                ..onStart = start
                ..onUpdate = update
                ..onEnd = end,
            ),
        VerticalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
          VerticalDragGestureRecognizer.new,
          (r) => r
            ..onStart = start
            ..onUpdate = update
            ..onEnd = end,
        ),
      };
    }
    return {
      ScaleGestureRecognizer: GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
        ScaleGestureRecognizer.new,
        (r) => r
          ..onStart = ((d) => _onStart(d.localFocalPoint))
          ..onUpdate = ((d) => _onUpdate(d.localFocalPoint, d.scale, d.pointerCount))
          ..onEnd = ((d) => _onEnd(d.velocity, d.pointerCount)),
      ),
      TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
        TapGestureRecognizer.new,
        (r) => r.onTap = () => setState(() => _chrome = !_chrome),
      ),
      DoubleTapGestureRecognizer: GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
        DoubleTapGestureRecognizer.new,
        (r) => r
          ..onDoubleTapDown = ((d) => _doubleTapAt = d.localPosition)
          ..onDoubleTap = _onDoubleTap,
      ),
    };
  }

  // ---- Build -------------------------------------------------------------------

  td.FormattedText? _captionOf(td.Message m) {
    td.FormattedText? own(td.Message x) => switch (x.content) {
      td.MessagePhoto(:final caption) ||
      td.MessageVideo(:final caption) ||
      td.MessageAnimation(:final caption) => caption.text.isEmpty ? null : caption,
      _ => null,
    };
    // An album carries one caption; every picture in it shows it.
    return own(m) ??
        (m.mediaAlbumId == 0
            ? null
            : widget.messages.where((x) => x.mediaAlbumId == m.mediaAlbumId).map(own).nonNulls.firstOrNull);
  }

  /// The current picture during a flight, or null when it rests.
  ({Rect clip, Rect image, double radius, double opacity})? _flightFrame(td.Message m) {
    final pictures = _Pictures.of(m);
    final aspect = pictures?.aspect ?? 16 / 9;
    final rest = _contentRect(m);
    final t = Curves.easeOutCubic.transform(_flightCtl.value);
    if (_closing) {
      final from = _closeFrom!;
      final to = _closeTo;
      if (to == null) {
        final shrink = Rect.fromCenter(
          center: from.image.center,
          width: from.image.width * (1 - 0.1 * t),
          height: from.image.height * (1 - 0.1 * t),
        );
        return (clip: Offset.zero & _size, image: shrink, radius: 0, opacity: 1 - t);
      }
      return (
        clip: Rect.lerp(from.clip, to, t)!,
        image: Rect.lerp(from.image, coverRect(aspect, to), t)!,
        radius: 10 * t,
        opacity: 1,
      );
    }
    if (_flightCtl.isCompleted) return null;
    final from = _openFrom;
    if (from == null) {
      final grow = Rect.fromCenter(
        center: rest.center,
        width: rest.width * (0.92 + 0.08 * t),
        height: rest.height * (0.92 + 0.08 * t),
      );
      return (clip: Offset.zero & _size, image: grow, radius: 0, opacity: t);
    }
    final f = flightFrame(t: t, aspect: aspect, from: from, to: rest);
    return (clip: f.clip, image: f.image, radius: 10 * (1 - t), opacity: 1);
  }

  Widget _pageAt(int i) {
    final m = widget.messages[i];
    final current = i == _index;
    final rest = _contentRect(m);
    final flight = current ? _flightFrame(m) : null;
    final pictures = _Pictures.of(m);
    final picture = pictures == null ? const SizedBox.shrink() : _Picture(pictures: pictures);

    Widget body;
    if (flight != null) {
      body = Opacity(
        opacity: flight.opacity.clamp(0.0, 1.0),
        child: ClipRRect(
          clipper: _RRectClipper(flight.clip, flight.radius),
          child: Stack(
            children: [Positioned.fromRect(rect: flight.image, child: picture)],
          ),
        ),
      );
    } else {
      final isVideo = m.content is! td.MessagePhoto;
      body = Stack(
        children: [
          Positioned.fromRect(rect: rest, child: picture),
          if (isVideo) Positioned.fill(child: _videoFor(m, active: current)),
        ],
      );
      if (current) {
        final matrix = Matrix4.identity()
          ..translateByDouble(_drag.dx, _drag.dy, 0, 1)
          ..translateByDouble(rest.center.dx, rest.center.dy, 0, 1)
          ..scaleByDouble(_dragScale, _dragScale, 1, 1)
          ..translateByDouble(-rest.center.dx, -rest.center.dy, 0, 1)
          ..translateByDouble(_zoom.offset.dx, _zoom.offset.dy, 0, 1)
          ..scaleByDouble(_zoom.scale, _zoom.scale, 1, 1);
        body = Transform(transform: matrix, child: body);
      }
    }
    return Positioned.fill(
      child: Transform.translate(
        offset: Offset((i - _pos) * _size.width, 0),
        child: KeyedSubtree(key: ValueKey(m.id), child: body),
      ),
    );
  }

  Widget _videoFor(td.Message m, {required bool active}) => switch (m.content) {
    td.MessageVideo(:final video) => _VideoPage(
      file: video.video,
      mime: video.mimeType,
      width: video.width,
      height: video.height,
      active: active,
      onChrome: (visible) => setState(() => _chrome = visible),
    ),
    td.MessageAnimation(:final animation) => _VideoPage(
      file: animation.animation,
      mime: animation.mimeType,
      width: animation.width,
      height: animation.height,
      loop: true,
      active: active,
      onChrome: (visible) => setState(() => _chrome = visible),
    ),
    _ => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final m = _message;
    final caption = _captionOf(m);
    final chrome = _chrome && !_closing && _flightCtl.isCompleted;
    return PopScope(
      canPop: _closed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          _size = constraints.biggest;
          final first = _pos.floor().clamp(0, widget.messages.length - 1);
          final pages = {first, (first + 1).clamp(0, widget.messages.length - 1), _index};
          return Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: Colors.black.withValues(alpha: _backdropOpacity)),
              ),
              Positioned.fill(
                child: RawGestureDetector(
                  behavior: HitTestBehavior.opaque,
                  gestures: _gestures,
                  child: Stack(
                    children: [
                      for (final i in pages) _pageAt(i),
                      // Videos: the caption shows while the controls are
                      // hidden and gives way to them on a tap. Photos: it
                      // follows the top bar. It sits under the gesture
                      // detector, so swipes over it still page and dismiss.
                      if (caption != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: AnimatedOpacity(
                            opacity: (m.content is td.MessageVideo ? !chrome : chrome) && !_closing ? 1 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Container(
                              key: const ValueKey('caption'),
                              width: double.infinity,
                              constraints: BoxConstraints(maxHeight: _size.height * 0.35),
                              padding: const EdgeInsets.fromLTRB(16, 32, 16, 28),
                              decoration: const BoxDecoration(
                                // Deep enough that white text reads over any frame.
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [Color(0xF2000000), Color(0xB3000000), Color(0x00000000)],
                                  stops: [0, 0.65, 1],
                                ),
                              ),
                              child: SafeArea(
                                top: false,
                                child: SingleChildScrollView(
                                  child: Semantics(
                                    label: 'Caption',
                                    child: FormattedTextView(
                                      caption,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        height: 1.35,
                                        shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              AnimatedOpacity(
                opacity: chrome ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !chrome,
                  child: SafeArea(
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                          onPressed: _close,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                m.isOutgoing ? 'You' : Display.senderName(cache, m.senderId),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                Display.listTime(Display.messageDate(m), DateTime.now()),
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        if (widget.messages.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: Text(
                              '${_index + 1} / ${widget.messages.length}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RRectClipper extends CustomClipper<RRect> {
  _RRectClipper(this.rect, this.radius);

  final Rect rect;
  final double radius;

  @override
  RRect getClip(Size size) => RRect.fromRectAndRadius(rect, Radius.circular(radius));

  @override
  bool shouldReclip(_RRectClipper old) => old.rect != rect || old.radius != radius;
}

/// The files a message's picture is drawn from: the chat tile's size (ready
/// at once, the flight starts on it) and the largest, layered on top as it
/// arrives.
class _Pictures {
  const _Pictures({required this.thumb, required this.full, required this.mini, required this.aspect});

  final td.File? thumb;
  final td.File? full;
  final td.Minithumbnail? mini;
  final double aspect;

  static _Pictures? of(td.Message m) {
    double ratio(int w, int h) => w > 0 && h > 0 ? w / h : 16 / 9;
    switch (m.content) {
      case td.MessagePhoto(:final photo):
        final big = largestSize(photo);
        if (big == null) return null;
        final sorted = [...photo.sizes]..sort((a, b) => a.width.compareTo(b.width));
        final tile = sorted.firstWhere((s) => s.width >= 640, orElse: () => sorted.last);
        return _Pictures(
          thumb: tile.photo,
          full: big.photo.id == tile.photo.id ? null : big.photo,
          mini: photo.minithumbnail,
          aspect: ratio(big.width, big.height),
        );
      case td.MessageVideo(:final video):
        return _Pictures(
          thumb: video.thumbnail?.file,
          full: null,
          mini: video.minithumbnail,
          aspect: ratio(video.width, video.height),
        );
      case td.MessageAnimation(:final animation):
        return _Pictures(
          thumb: animation.thumbnail?.file,
          full: null,
          mini: animation.minithumbnail,
          aspect: ratio(animation.width, animation.height),
        );
      default:
        return null;
    }
  }
}

class _Picture extends StatelessWidget {
  const _Picture({required this.pictures});

  final _Pictures pictures;

  @override
  Widget build(BuildContext context) {
    final mini = Display.minithumbnail(pictures.mini);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (pictures.thumb case final thumb?)
          TdFileImage(
            file: thumb,
            fit: BoxFit.fill,
            placeholderBytes: mini,
            fullResolution: true,
            semanticLabel: 'Photo',
          )
        else if (mini != null)
          Image.memory(mini, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium),
        if (pictures.full case final full?)
          TdFileImage(file: full, fit: BoxFit.fill, priority: 32, fullResolution: true),
      ],
    );
  }
}

/// Resolves a video to a local path or a loopback stream URL, then plays.
class _VideoPage extends StatefulWidget {
  const _VideoPage({
    required this.file,
    required this.mime,
    required this.width,
    required this.height,
    required this.onChrome,
    this.loop = false,
    this.active = true,
  });

  final td.File file;
  final String mime;
  final int width;
  final int height;
  final ValueChanged<bool> onChrome;
  final bool loop;

  /// Off-screen neighbours stay paused.
  final bool active;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  ({String source, bool local})? _source;

  /// The player stays invisible over the thumbnail until its first frame, so
  /// opening never flashes black or a stretched frame.
  var _firstFrame = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  Future<void> _resolve() async {
    if (_source != null) return;
    final files = context.read<FileStore>();
    final f = files[widget.file.id] ?? widget.file;
    if (f.local.isDownloadingCompleted && f.local.path.isNotEmpty) {
      setState(() => _source = (source: f.local.path, local: true));
      return;
    }
    final url = await context.read<TdStreamServer>().urlFor(
      f,
      mimeType: widget.mime.isEmpty ? 'video/mp4' : widget.mime,
    );
    if (mounted) setState(() => _source = (source: url.toString(), local: false));
  }

  @override
  Widget build(BuildContext context) {
    final s = _source;
    if (s == null) return const SizedBox.expand();
    return Opacity(
      opacity: _firstFrame ? 1 : 0,
      child: VideoPlayerView(
        source: s.source,
        isLocalFile: s.local,
        aspectRatio: widget.height == 0 ? null : widget.width / widget.height,
        loop: widget.loop,
        paused: !widget.active,
        prefs: context.read<AppPreferences>(),
        onControlsVisibilityChanged: widget.onChrome,
        onProgress: (position, _, _) {
          if (!_firstFrame && position > Duration.zero && mounted) setState(() => _firstFrame = true);
        },
        fileId: widget.file.id,
      ),
    );
  }
}

/// Zooms by [scale] about [focal], keeping that point where it is.
Matrix4 zoomAt(Offset focal, double scale) => Matrix4.identity()
  ..translateByDouble(-focal.dx * (scale - 1), -focal.dy * (scale - 1), 0, 1)
  ..scaleByDouble(scale, scale, 1, 1);

/// Double tap zooms in about the tap (or back out), animated rather than
/// jumping.
class DoubleTapZoom extends StatefulWidget {
  const DoubleTapZoom({
    super.key,
    required this.controller,
    required this.child,
    this.onTap,
    this.scale = 2.5,
  });

  final TransformationController controller;
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<DoubleTapZoom> createState() => _DoubleTapZoomState();
}

class _DoubleTapZoomState extends State<DoubleTapZoom> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 280))
    ..addListener(_tick);
  Animation<Matrix4>? _tween;
  Offset _focal = Offset.zero;

  void _tick() {
    if (_tween != null) widget.controller.value = _tween!.value;
  }

  void _toggle() {
    final zoomed = widget.controller.value.getMaxScaleOnAxis() > 1.01;
    _tween = Matrix4Tween(
      begin: widget.controller.value,
      end: zoomed ? Matrix4.identity() : zoomAt(_focal, widget.scale),
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward(from: 0);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onTap,
    onDoubleTapDown: (d) => _focal = d.localPosition,
    onDoubleTap: _toggle,
    child: widget.child,
  );
}
