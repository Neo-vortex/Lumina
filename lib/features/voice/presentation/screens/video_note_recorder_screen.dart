import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/media/ffmpeg_service.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/theme/glow_colors.dart';

/// Records a round video message with the front camera (≤ 60 s), crops it
/// to a 384 px square and returns TDLib input content.
class VideoNoteRecorderScreen extends StatefulWidget {
  const VideoNoteRecorderScreen({super.key});

  static Future<td.InputMessageContent?> open(BuildContext context) => Navigator.of(context)
      .push<td.InputMessageContent>(
        MaterialPageRoute(builder: (_) => const VideoNoteRecorderScreen(), fullscreenDialog: true),
      );

  @override
  State<VideoNoteRecorderScreen> createState() => _VideoNoteRecorderScreenState();
}

class _VideoNoteRecorderScreenState extends State<VideoNoteRecorderScreen> {
  CameraController? _camera;
  String? _error;
  var _recording = false;
  var _processing = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  static const _max = Duration(seconds: 60);
  static const _side = 384;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final cam = videoNoteCamera(front);
      await cam.initialize();
      if (!mounted) return;
      setState(() => _camera = cam);
    } on CameraException catch (e) {
      setState(() => _error = e.description ?? e.code);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final cam = _camera;
    if (cam == null || _processing) return;
    if (!_recording) {
      await cam.startVideoRecording();
      await _brighten(cam);
      HapticFeedback.lightImpact();
      _elapsed = Duration.zero;
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        setState(() => _elapsed += const Duration(milliseconds: 200));
        if (_elapsed >= _max) _toggle();
      });
      setState(() => _recording = true);
      return;
    }
    _timer?.cancel();
    final file = await cam.stopVideoRecording();
    unawaited(cam.setExposureOffset(0).then((_) {}, onError: (Object _) {}));
    setState(() {
      _recording = false;
      _processing = true;
    });
    final content = await _process(file.path);
    if (!mounted) return;
    if (content == null) {
      setState(() {
        _processing = false;
        _error = 'Could not process the video';
      });
    } else {
      Navigator.pop(context, content);
    }
  }

  /// Recording rebinds CameraX onto the video template, which exposes the front
  /// camera darker than the preview on many phones (the fixed frame rate alone
  /// did not prevent it). A one-stop exposure boost while recording brings it
  /// back in line, within what the camera supports.
  static const _recordingBoostEv = 1.0;

  Future<void> _brighten(CameraController cam) async {
    try {
      final max = await cam.getMaxExposureOffset();
      if (max <= 0) return;
      final step = await cam.getExposureOffsetStepSize();
      var ev = _recordingBoostEv.clamp(0.0, max);
      if (step > 0) ev = (ev / step).round() * step;
      await cam.setExposureOffset(ev);
    } on CameraException {
      // Exposure compensation unsupported: record as is.
    }
  }

  Future<td.InputMessageContent?> _process(String input) async {
    final ffmpeg = context.read<FfmpegService>();
    final out = await ffmpeg.tempPath('mp4');
    // Centre-crop to a square, scale to 384 px, mirror like the preview.
    final filter = 'crop=min(iw\\,ih):min(iw\\,ih),scale=$_side:$_side,hflip,format=yuv420p';
    var ok = await ffmpeg.run([
      '-i', input, '-vf', filter, //
      '-c:v', 'h264_mediacodec', '-b:v', '900k', '-c:a', 'aac', '-b:a', '64k', '-ac', '1',
      '-movflags', '+faststart', out,
    ]);
    if (!ok) {
      ok = await ffmpeg.run([
        '-i', input, '-vf', filter, //
        '-c:v', 'mpeg4', '-qscale:v', '5', '-c:a', 'aac', '-b:a', '64k', '-ac', '1',
        '-movflags', '+faststart', out,
      ]);
    }
    if (!ok) return null;
    final probe = await ffmpeg.probe(out);
    final thumb = await ffmpeg.thumbnail(out, at: Duration.zero);
    return td.InputMessageVideoNote(
      videoNote: td.InputVideoNote(
        videoNote: td.InputFileLocal(path: out),
        thumbnail: thumb == null
            ? null
            : td.InputThumbnail(thumbnail: td.InputFileLocal(path: thumb), width: 320, height: 320),
        duration: probe?.duration.inSeconds ?? _elapsed.inSeconds,
        length: _side,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cam = _camera;
    final size = MediaQuery.sizeOf(context).width * 0.8;
    return Scaffold(
      backgroundColor: GlowColors.backgroundDeep,
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Round video')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _recording ? GlowColors.coral : GlowColors.cyan, width: 3),
                boxShadow: glow(
                  _recording ? GlowColors.coral : GlowColors.cyan,
                  intensity: _recording ? 1 : 0.4,
                ),
              ),
              child: ClipOval(
                child: _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                      )
                    : cam == null || !cam.value.isInitialized
                    ? const Center(child: CircularProgressIndicator())
                    : FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: cam.value.previewSize?.height ?? size,
                          height: cam.value.previewSize?.width ?? size,
                          child: CameraPreview(cam),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            Semantics(
              liveRegion: _recording,
              child: Text(
                _processing
                    ? 'Preparing…'
                    : _recording
                    ? '${Display.duration(_elapsed.inSeconds)} / ${Display.duration(_max.inSeconds)}'
                    : 'Tap to record',
                style: const TextStyle(color: GlowColors.textMuted),
              ),
            ),
            const SizedBox(height: 24),
            Semantics(
              button: true,
              label: _recording ? 'Stop and send' : 'Start recording',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: _toggle,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [GlowColors.violetDeep, GlowColors.magentaDeep]),
                    boxShadow: glow(GlowColors.magenta),
                  ),
                  child: _processing
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : Icon(
                          _recording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CameraX binds video capture only when recording starts, and that rebind
/// switches auto-exposure to the video stream's frame-rate range, so the
/// picture darkened the moment recording began. A fixed rate set up front
/// keeps preview and recording on the same exposure; 24 fps allows ~41 ms
/// exposures, brighter indoors than 30.
CameraController videoNoteCamera(CameraDescription camera) =>
    CameraController(camera, ResolutionPreset.medium, enableAudio: true, fps: 24);
