import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:path_provider/path_provider.dart';

/// What ffprobe found in a media file.
class MediaProbe {
  const MediaProbe({
    required this.path,
    required this.sizeBytes,
    required this.duration,
    required this.width,
    required this.height,
    required this.videoCodec,
    required this.audioCodec,
    required this.bitrate,
    required this.pixelFormat,
    required this.frameRate,
    required this.rotation,
  });

  final String path;
  final int sizeBytes;
  final Duration duration;

  /// Display dimensions (rotation applied).
  final int width;
  final int height;
  final String? videoCodec;
  final String? audioCodec;

  /// Overall bits per second, 0 if unknown.
  final int bitrate;
  final String? pixelFormat;
  final double? frameRate;
  final int rotation;

  bool get hasVideo => videoCodec != null;
  bool get hasAudio => audioCodec != null;
  int get shortSide => width < height ? width : height;
}

/// Thin wrapper over FFmpegKit. This is the LGPL `full` build: no x264/x265
/// (GPL), so H.264/H.265 encoding uses the device's hardware MediaCodec
/// encoders, which are also the fastest and most battery-friendly option.
class FfmpegService {
  Set<String>? _encoders;

  Future<MediaProbe?> probe(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();
    if (info == null) return null;
    String? video, audio, pix;
    var w = 0, h = 0, rotation = 0;
    double? fps;
    for (final s in info.getStreams()) {
      final type = s.getType();
      if (type == 'video' && video == null) {
        video = s.getCodec();
        w = s.getWidth() ?? 0;
        h = s.getHeight() ?? 0;
        pix = s.getAllProperties()?['pix_fmt'] as String?;
        fps = _parseRate(s.getAverageFrameRate());
        rotation = _rotation(s.getAllProperties());
      } else if (type == 'audio' && audio == null) {
        audio = s.getCodec();
      }
    }
    if (rotation.abs() % 180 == 90) (w, h) = (h, w);
    final seconds = double.tryParse(info.getDuration() ?? '') ?? 0;
    return MediaProbe(
      path: path,
      sizeBytes: int.tryParse(info.getSize() ?? '') ?? await File(path).length(),
      duration: Duration(milliseconds: (seconds * 1000).round()),
      width: w,
      height: h,
      videoCodec: video,
      audioCodec: audio,
      bitrate: int.tryParse(info.getBitrate() ?? '') ?? 0,
      pixelFormat: pix,
      frameRate: fps,
      rotation: rotation,
    );
  }

  static double? _parseRate(String? r) {
    if (r == null || !r.contains('/')) return double.tryParse(r ?? '');
    final [a, b] = r.split('/').map(double.tryParse).toList();
    if (a == null || b == null || b == 0) return null;
    return a / b;
  }

  static int _rotation(Map<dynamic, dynamic>? props) {
    final tags = props?['tags'];
    if (tags is Map && tags['rotate'] != null) return int.tryParse('${tags['rotate']}') ?? 0;
    final side = props?['side_data_list'];
    if (side is List) {
      for (final d in side) {
        if (d is Map && d['rotation'] != null) return (d['rotation'] as num).toInt();
      }
    }
    return 0;
  }

  /// Video encoders compiled into this build (cached).
  Future<Set<String>> encoders() async {
    final cached = _encoders;
    if (cached != null) return cached;
    final session = await FFmpegKit.execute('-hide_banner -encoders');
    final out = await session.getOutput() ?? '';
    final found = <String>{};
    for (final line in out.split('\n')) {
      final m = RegExp(r'^\s*V[\.\w]{5}\s+(\S+)').firstMatch(line);
      if (m != null) found.add(m.group(1)!);
    }
    return _encoders = found;
  }

  /// Runs ffmpeg with [args]. [onProgress] gets 0..1 based on [duration].
  /// Returns true on success; false when cancelled or failed.
  Future<bool> run(
    List<String> args, {
    Duration? duration,
    void Function(double progress)? onProgress,
    FfmpegCancelToken? cancel,
  }) async {
    final done = Completer<bool>();
    final session = await FFmpegKit.executeWithArgumentsAsync(
      ['-hide_banner', '-y', ...args],
      (session) async {
        final code = await session.getReturnCode();
        if (!done.isCompleted) done.complete(ReturnCode.isSuccess(code));
      },
      null,
      (stats) {
        final total = duration?.inMilliseconds ?? 0;
        if (total > 0 && onProgress != null) onProgress((stats.getTime() / total).clamp(0.0, 1.0));
      },
    );
    cancel?._attach(() => FFmpegKit.cancel(session.getSessionId()));
    return done.future;
  }

  /// A fresh path in the app's cache directory.
  Future<String> tempPath(String extension) async {
    final dir = await getTemporaryDirectory();
    final folder = Directory('${dir.path}/media')..createSync(recursive: true);
    return '${folder.path}/${DateTime.now().microsecondsSinceEpoch}.$extension';
  }

  /// JPEG frame at [at] for video thumbnails (Telegram wants ≤ 320 px).
  Future<String?> thumbnail(String video, {Duration at = const Duration(milliseconds: 500)}) async {
    final out = await tempPath('jpg');
    final ok = await run([
      '-ss',
      (at.inMilliseconds / 1000).toStringAsFixed(2),
      '-i',
      video,
      '-frames:v',
      '1',
      '-vf',
      "scale='if(gt(iw,ih),320,-2)':'if(gt(iw,ih),-2,320)'",
      '-q:v',
      '4',
      out,
    ]);
    return ok ? out : null;
  }

  /// Any audio → 16 kHz mono 16-bit WAV (Whisper input, spec §7.2/§7.4).
  Future<String?> toWhisperWav(String input) async {
    final out = await tempPath('wav');
    final ok = await run(['-i', input, '-vn', '-ac', '1', '-ar', '16000', '-c:a', 'pcm_s16le', out]);
    return ok ? out : null;
  }

  /// WAV/any → OGG/Opus voice note, the format Telegram clients expect.
  Future<String?> toVoiceNote(String input) async {
    final out = await tempPath('ogg');
    final ok = await run([
      '-i',
      input,
      '-vn',
      '-ac',
      '1',
      '-ar',
      '48000',
      '-c:a',
      'libopus',
      '-b:a',
      '32k',
      '-application',
      'voip',
      out,
    ]);
    return ok ? out : null;
  }

  /// Deletes conversion outputs older than [age]. TDLib reads a local file
  /// while uploading it, so outputs must outlive the send call; this runs
  /// at startup instead.
  Future<void> purgeTemp({Duration age = const Duration(days: 1)}) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/media');
    if (!await dir.exists()) return;
    final cutoff = DateTime.now().subtract(age);
    await for (final f in dir.list()) {
      if (f is File && (await f.lastModified()).isBefore(cutoff)) await f.delete().catchError((_) => f);
    }
  }

  static Future<void> configure() async {
    // Keep FFmpeg's own log noise out of release builds.
    await FFmpegKitConfig.enableLogs();
  }
}

/// Cancels a running [FfmpegService.run].
class FfmpegCancelToken {
  void Function()? _cancel;
  var _cancelled = false;

  bool get isCancelled => _cancelled;

  void _attach(void Function() cancel) {
    _cancel = cancel;
    if (_cancelled) cancel();
  }

  void cancel() {
    _cancelled = true;
    _cancel?.call();
  }
}
