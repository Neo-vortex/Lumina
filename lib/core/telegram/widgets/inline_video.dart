import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

import '../../widgets/chat_scrolling.dart';
import 'progressive_image.dart';

/// A downloaded video playing inside its chat bubble: small play/pause and
/// mute buttons in the corner, the rest of the tile still opens the full
/// viewer (the caller's tap). Nothing plays until asked, unless [autoplay]
/// (Settings → Autoplay videos in chats): then it starts muted once the
/// list stops on it, like GIFs, and holds still while the list moves.
///
/// Played by hand, it stops at the end back on its first frame; autoplayed,
/// it loops.
class InlineVideo extends StatefulWidget {
  const InlineVideo({super.key, required this.path, required this.still, this.autoplay = false});

  /// Raised while a full-screen player is up: every inline video pauses
  /// (the viewer plays its own, often the same clip).
  static final hold = ValueNotifier<int>(0);

  final String path;

  /// The thumbnail, shown until the first frame and whenever stopped.
  final Widget still;
  final bool autoplay;

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> with SingleTickerProviderStateMixin {
  VideoPlayerController? _player;
  var _ready = false;
  var _muted = true;

  /// The user pressed play (not autoplay): no loop, stop at the end.
  var _manual = false;
  var _playing = false;

  // Video frames alone don't schedule Flutter frames here (see LoopingGif).
  late final Ticker _frames = createTicker((_) {});
  Timer? _dwell;

  @override
  void initState() {
    super.initState();
    ChatScrolling.moving.addListener(_onScroll);
    InlineVideo.hold.addListener(_onHold);
    if (widget.autoplay) _onScroll();
  }

  void _onHold() {
    if (InlineVideo.hold.value > 0) {
      if (_playing) _pause();
    }
  }

  @override
  void didUpdateWidget(InlineVideo old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _stop(dispose: true);
      if (widget.autoplay) _onScroll();
    } else if (old.autoplay && !widget.autoplay && !_manual) {
      _stop(dispose: true);
    } else if (!old.autoplay && widget.autoplay) {
      _onScroll();
    }
  }

  void _onScroll() {
    _dwell?.cancel();
    if (ChatScrolling.moving.value) {
      // Autoplay holds still while the list moves; a video the user started
      // keeps going.
      if (!_manual && _playing) _player?.pause();
      return;
    }
    if (!widget.autoplay || _manual || InlineVideo.hold.value > 0) return;
    _dwell = Timer(const Duration(milliseconds: 350), () {
      if (mounted && !ChatScrolling.moving.value) _play(manual: false);
    });
  }

  Future<void> _play({required bool manual}) async {
    _manual = manual;
    var p = _player;
    if (p == null) {
      p = _player = VideoPlayerController.file(File(widget.path));
      p.addListener(_onTick);
      try {
        await p.initialize();
      } catch (_) {
        if (mounted) setState(() => _player = null);
        p.dispose();
        return;
      }
      if (!mounted || _player != p) return;
      _ready = true;
    }
    await p.setVolume(_muted ? 0 : 1);
    await p.setLooping(!_manual);
    // Ended earlier: from the top.
    final v = p.value;
    if (v.duration > Duration.zero && v.position >= v.duration) await p.seekTo(Duration.zero);
    await p.play();
    if (!_frames.isActive) _frames.start();
    if (mounted) setState(() => _playing = true);
  }

  void _pause() {
    _player?.pause();
    if (_frames.isActive) _frames.stop();
    setState(() {
      _playing = false;
      // Paused by hand: autoplay doesn't take it over again.
      _manual = true;
    });
  }

  void _onTick() {
    final p = _player;
    if (p == null || !_manual || !_playing) return;
    final v = p.value;
    if (v.isInitialized && !v.isLooping && v.duration > Duration.zero && v.position >= v.duration && !v.isPlaying) {
      // Back to the first frame, play button up.
      p.seekTo(Duration.zero);
      if (_frames.isActive) _frames.stop();
      if (mounted) setState(() => _playing = false);
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _player?.setVolume(_muted ? 0 : 1);
    // Unmuting a still video means "let me hear it".
    if (!_muted && !_playing) _play(manual: true);
  }

  void _stop({bool dispose = false}) {
    _dwell?.cancel();
    if (_frames.isActive) _frames.stop();
    final p = _player;
    if (dispose && p != null) {
      p.removeListener(_onTick);
      _player = null;
      _ready = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => p.dispose());
    } else {
      p?.pause();
    }
    _playing = false;
    _manual = false;
  }

  @override
  void dispose() {
    ChatScrolling.moving.removeListener(_onScroll);
    InlineVideo.hold.removeListener(_onHold);
    _dwell?.cancel();
    _frames.dispose();
    _player?.removeListener(_onTick);
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _player;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.still,
        if (_ready && p != null)
          FadeInOnce(
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(width: p.value.size.width, height: p.value.size.height, child: VideoPlayer(p)),
            ),
          ),
        Positioned(
          left: 6,
          bottom: 6,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MiniButton(
                icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                label: _playing ? 'Pause' : 'Play here',
                onTap: () => _playing ? _pause() : _play(manual: true),
              ),
              const SizedBox(width: 6),
              _MiniButton(
                icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                label: _muted ? 'Unmute' : 'Mute',
                onTap: _toggleMute,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A 30 dp round button over the video (with a 44 dp touch target).
class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.55)),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    ),
  );
}
