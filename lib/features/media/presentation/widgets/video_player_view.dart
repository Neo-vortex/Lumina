import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../../../core/storage/app_preferences.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/theme/glow_colors.dart';

/// libVLC playback with the spec's gestures (§7.1):
/// * double-tap left/right: −/+10 s
/// * horizontal drag: scrub, with a timestamp bubble
/// * vertical drag: brightness (left half) / volume (right half)
/// * pinch: zoom (1×–4×)
///
/// [url] is either a local file path or the loopback stream URL, so
/// playback starts before TDLib finishes downloading.
class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({
    super.key,
    required this.source,
    required this.isLocalFile,
    this.aspectRatio,
    this.loop = false,
    this.muted = false,
    this.showControls = true,
    this.prefs,
  });

  final String source;
  final bool isLocalFile;
  final double? aspectRatio;
  final bool loop;
  final bool muted;
  final bool showControls;
  final AppPreferences? prefs;

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

enum _Drag { none, scrub, brightness, volume }

class _VideoPlayerViewState extends State<VideoPlayerView> {
  late final VlcPlayerController _vlc = widget.isLocalFile
      ? VlcPlayerController.file(
          File(widget.source),
          hwAcc: HwAcc.full,
          autoPlay: true,
          options: VlcPlayerOptions(),
        )
      : VlcPlayerController.network(
          widget.source,
          hwAcc: HwAcc.full,
          autoPlay: true,
          options: VlcPlayerOptions(advanced: VlcAdvancedOptions([VlcAdvancedOptions.networkCaching(1500)])),
        );

  var _controlsVisible = true;
  Timer? _hideTimer;
  var _drag = _Drag.none;
  Offset _dragStart = Offset.zero;
  Duration _scrubTarget = Duration.zero;
  Duration _scrubFrom = Duration.zero;
  double _brightness = 0.5;
  int _volume = 100;
  double _scale = 1, _scaleStart = 1;
  String? _toast;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _vlc.addListener(_onValue);
    _scheduleHide();
    ScreenBrightness.instance.application.then((b) => _brightness = b).ignore();
    if (widget.muted) _volume = 0;
  }

  var _configured = false;

  void _onValue() {
    final v = _vlc.value;
    if (v.isInitialized && !_configured) {
      _configured = true;
      _vlc.setLooping(widget.loop);
      if (widget.muted) _vlc.setVolume(0);
      final speed = widget.prefs?.playbackSpeed;
      if (speed != null && speed != 1 && !widget.loop) _vlc.setPlaybackSpeed(speed.clamp(0.5, 2.0));
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _toastTimer?.cancel();
    _vlc.removeListener(_onValue);
    _vlc.dispose();
    ScreenBrightness.instance.resetApplicationScreenBrightness().ignore();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _vlc.value.isPlaying) setState(() => _controlsVisible = false);
    });
  }

  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _seekBy(Duration delta) async {
    final v = _vlc.value;
    var target = v.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (v.duration > Duration.zero && target > v.duration) target = v.duration;
    await _vlc.seekTo(target);
    HapticFeedback.selectionClick();
    _showToast('${delta.isNegative ? '−' : '+'}${delta.inSeconds.abs()} s');
  }

  void _togglePlay() {
    _vlc.value.isPlaying ? _vlc.pause() : _vlc.play();
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  // One recognizer handles pan (1 finger) and pinch (2 fingers).
  void _onScaleStart(ScaleStartDetails d) {
    _scaleStart = _scale;
    _dragStart = d.localFocalPoint;
    _drag = _Drag.none;
    _scrubFrom = _vlc.value.position;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    if (d.pointerCount >= 2) {
      setState(() => _scale = (_scaleStart * d.scale).clamp(1.0, 4.0));
      return;
    }
    final delta = d.localFocalPoint - _dragStart;
    if (_drag == _Drag.none && delta.distance > 18) {
      _drag = delta.dx.abs() > delta.dy.abs()
          ? _Drag.scrub
          : (_dragStart.dx < size.width / 2 ? _Drag.brightness : _Drag.volume);
    }
    switch (_drag) {
      case _Drag.scrub:
        final total = _vlc.value.duration;
        if (total <= Duration.zero) return;
        // Full width ≈ 90 s, or the whole video if shorter.
        final span = total.inMilliseconds < 90000 ? total.inMilliseconds : 90000;
        final ms = (_scrubFrom.inMilliseconds + delta.dx / size.width * span)
            .clamp(0, total.inMilliseconds)
            .round();
        setState(() => _scrubTarget = Duration(milliseconds: ms));
      case _Drag.brightness:
        _brightness = (_brightness - d.focalPointDelta.dy / size.height).clamp(0.0, 1.0);
        ScreenBrightness.instance.setApplicationScreenBrightness(_brightness).ignore();
        _showToast('Brightness ${(_brightness * 100).round()} %');
      case _Drag.volume:
        _volume = (_volume - d.focalPointDelta.dy / size.height * 120).clamp(0, 100).round();
        _vlc.setVolume(_volume);
        _showToast('Volume $_volume %');
      case _Drag.none:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_drag == _Drag.scrub) _vlc.seekTo(_scrubTarget);
    setState(() => _drag = _Drag.none);
  }

  @override
  Widget build(BuildContext context) {
    final v = _vlc.value;
    final ratio =
        widget.aspectRatio ?? (v.size.width > 0 && v.size.height > 0 ? v.size.width / v.size.height : 16 / 9);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Semantics(
          label: 'Video player. Double tap sides to skip 10 seconds',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _controlsVisible = !_controlsVisible);
              if (_controlsVisible) _scheduleHide();
            },
            onDoubleTapDown: (d) =>
                _seekBy(Duration(seconds: d.localPosition.dx < size.width / 2 ? -10 : 10)),
            onDoubleTap: () {},
            onScaleStart: widget.showControls ? _onScaleStart : null,
            onScaleUpdate: widget.showControls ? (d) => _onScaleUpdate(d, size) : null,
            onScaleEnd: widget.showControls ? _onScaleEnd : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Transform.scale(
                    scale: _scale,
                    child: VlcPlayer(
                      controller: _vlc,
                      aspectRatio: ratio,
                      placeholder: const Center(child: CircularProgressIndicator(color: GlowColors.violet)),
                    ),
                  ),
                ),
                if (v.isBuffering)
                  const Center(child: CircularProgressIndicator(color: GlowColors.cyan, strokeWidth: 2.4)),
                if (_drag == _Drag.scrub)
                  Center(child: _Bubble('${_fmt(_scrubTarget)} / ${_fmt(v.duration)}')),
                if (_toast != null) Align(alignment: const Alignment(0, -0.6), child: _Bubble(_toast!)),
                if (widget.showControls)
                  AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: _Controls(
                        controller: _vlc,
                        onPlayPause: _togglePlay,
                        onSeek: (d) {
                          _vlc.seekTo(d);
                          _scheduleHide();
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _fmt(Duration d) => Display.duration(d.inSeconds);
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller, required this.onPlayPause, required this.onSeek});

  final VlcPlayerController controller;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final v = controller.value;
    final total = v.duration.inMilliseconds.toDouble();
    final pos = v.position.inMilliseconds.toDouble().clamp(0.0, total <= 0 ? 0.0 : total);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.center,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: IconButton(
              iconSize: 64,
              tooltip: v.isPlaying ? 'Pause' : 'Play',
              onPressed: onPlayPause,
              icon: Icon(
                v.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                color: Colors.white,
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Text(
                    Display.duration(v.position.inSeconds),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  Expanded(
                    child: Slider(
                      value: pos,
                      max: total <= 0 ? 1 : total,
                      activeColor: GlowColors.cyan,
                      inactiveColor: Colors.white24,
                      onChanged: total <= 0 ? null : (x) => onSeek(Duration(milliseconds: x.round())),
                    ),
                  ),
                  Text(
                    Display.duration(v.duration.inSeconds),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  PopupMenuButton<double>(
                    tooltip: 'Playback speed',
                    icon: Text('${v.playbackSpeed}×', style: const TextStyle(color: Colors.white)),
                    onSelected: controller.setPlaybackSpeed,
                    itemBuilder: (_) => [
                      for (final s in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                        PopupMenuItem(value: s, child: Text('$s×')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
