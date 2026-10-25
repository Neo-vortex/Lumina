import 'dart:math' as math;

import '../../../core/media/ffmpeg_service.dart';

/// Output video codec choices for the advanced converter.
enum VideoCodec {
  h264('H.264 (most compatible)', 'h264_mediacodec', 'mp4'),
  h265('H.265 / HEVC (smaller, newer phones)', 'hevc_mediacodec', 'mp4'),
  vp9('VP9 (open, slow software encode)', 'libvpx-vp9', 'webm'),
  mpeg4('MPEG-4 Part 2 (very old devices)', 'mpeg4', 'mp4');

  const VideoCodec(this.label, this.encoder, this.container);
  final String label;
  final String encoder;
  final String container;
}

enum AudioChoice {
  aac128('AAC 128 kbps', 'aac', 128),
  aac96('AAC 96 kbps', 'aac', 96),
  aac64('AAC 64 kbps', 'aac', 64),
  opus64('Opus 64 kbps', 'libopus', 64),
  opus32('Opus 32 kbps', 'libopus', 32),
  none('No audio', null, 0);

  const AudioChoice(this.label, this.encoder, this.kbps);
  final String label;
  final String? encoder;
  final int kbps;
}

/// One way to send a video: original or a transcode.
class VideoPreset {
  const VideoPreset({
    required this.id,
    required this.title,
    required this.description,
    this.codec,
    this.shortSide,
    this.videoKbps = 0,
    this.audio = AudioChoice.aac128,
    this.fps,
  });

  /// "Send as is".
  const VideoPreset.original(this.description)
    : id = 'original',
      title = 'Original',
      codec = null,
      shortSide = null,
      videoKbps = 0,
      audio = AudioChoice.aac128,
      fps = null;

  final String id;
  final String title;
  final String description;

  /// Null means no transcode.
  final VideoCodec? codec;

  /// Target length of the shorter side (720 = "720p" in either orientation);
  /// null keeps the source size.
  final int? shortSide;
  final int videoKbps;
  final AudioChoice audio;
  final int? fps;

  bool get isOriginal => codec == null;

  /// Estimated output size for [probe].
  int estimateBytes(MediaProbe probe) {
    if (isOriginal) return probe.sizeBytes;
    final seconds = probe.duration.inMilliseconds / 1000;
    final audioKbps = probe.hasAudio ? audio.kbps : 0;
    // ~3 % container overhead.
    return ((videoKbps + audioKbps) * 1000 / 8 * seconds * 1.03).round();
  }

  /// ffmpeg arguments that turn [input] into [output].
  List<String> ffmpegArgs(MediaProbe probe, String input, String output) {
    final codec = this.codec!;
    final args = <String>[
      '-i',
      input,
      '-map',
      '0:v:0',
      if (probe.hasAudio && audio != AudioChoice.none) ...['-map', '0:a:0?'],
    ];
    final filters = <String>[];
    final target = shortSide;
    if (target != null && probe.shortSide > target) {
      // Scale the shorter side to [target] in either orientation; keep even.
      filters.add("scale='if(gt(iw,ih),-2,$target)':'if(gt(iw,ih),$target,-2)'");
    }
    if (fps != null && (probe.frameRate ?? 0) > fps! + 0.5) filters.add('fps=$fps');
    // 8-bit 4:2:0 is what old decoders and hardware encoders accept.
    filters.add('format=yuv420p');
    args.addAll(['-vf', filters.join(',')]);

    args.addAll(['-c:v', codec.encoder, '-b:v', '${videoKbps}k']);
    switch (codec) {
      case VideoCodec.h264:
        // Main profile, level 4.0: plays on essentially every Android since 4.x.
        args.addAll(['-profile:v', 'main', '-level', '40', '-g', '60']);
      case VideoCodec.h265:
        args.addAll(['-g', '60']);
      case VideoCodec.vp9:
        args.addAll(['-deadline', 'realtime', '-cpu-used', '8', '-row-mt', '1']);
      case VideoCodec.mpeg4:
        args.addAll(['-qscale:v', '4']);
    }

    if (!probe.hasAudio || audio == AudioChoice.none) {
      args.add('-an');
    } else {
      final enc = codec == VideoCodec.vp9 ? 'libopus' : audio.encoder!;
      args.addAll(['-c:a', enc, '-b:a', '${audio.kbps}k', '-ac', '2']);
    }
    if (codec.container == 'mp4') args.addAll(['-movflags', '+faststart']);
    args.add(output);
    return args;
  }
}

/// Codecs that mid-range and older phones often cannot decode in hardware.
bool needsCompatibility(MediaProbe probe) {
  final c = probe.videoCodec?.toLowerCase() ?? '';
  final tenBit = (probe.pixelFormat ?? '').contains('10');
  return c.contains('hevc') ||
      c.contains('h265') ||
      c.contains('vp9') ||
      c.contains('av1') ||
      c.contains('prores') ||
      tenBit;
}

/// Bitrate that looks good for a given short side (H.264).
int recommendedKbps(int shortSide, {VideoCodec codec = VideoCodec.h264}) {
  final base = switch (shortSide) {
    >= 1080 => 5000,
    >= 720 => 2500,
    >= 540 => 1500,
    >= 480 => 1100,
    _ => 700,
  };
  return switch (codec) {
    VideoCodec.h265 || VideoCodec.vp9 => (base * 0.65).round(),
    VideoCodec.mpeg4 => (base * 1.4).round(),
    VideoCodec.h264 => base,
  };
}

/// The "simple" choices (user request): original, two smaller variants,
/// and a compatibility transcode when the source uses a codec older or
/// mid-range phones struggle with.
List<VideoPreset> simplePresets(MediaProbe probe) {
  final presets = <VideoPreset>[const VideoPreset.original('Best quality, largest file')];
  final short = probe.shortSide;
  final sourceKbps = probe.bitrate > 0 ? probe.bitrate ~/ 1000 : 8000;

  // Two reduced variants below the source size.
  final ladder = [720, 480, 360].where((s) => s < short).toList();
  if (ladder.isEmpty && short > 0) ladder.add(short);
  for (final s in ladder.take(2)) {
    final kbps = math.min(recommendedKbps(s), (sourceKbps * 0.8).round());
    presets.add(
      VideoPreset(
        id: 'reduced-$s',
        title: s == ladder.first ? 'Balanced · ${s}p' : 'Small · ${s}p',
        description: s == ladder.first ? 'Good quality, much smaller' : 'Smallest, fine for phones',
        codec: VideoCodec.h264,
        shortSide: s,
        videoKbps: math.max(kbps, 300),
        audio: s == ladder.first ? AudioChoice.aac128 : AudioChoice.aac64,
        fps: 30,
      ),
    );
  }

  if (needsCompatibility(probe)) {
    final s = math.min(short, 1080);
    presets.add(
      VideoPreset(
        id: 'compatible',
        title: 'Compatible · H.264',
        description: 'Re-encodes ${probe.videoCodec?.toUpperCase()} so older phones can play it',
        codec: VideoCodec.h264,
        shortSide: s,
        videoKbps: recommendedKbps(s),
        audio: AudioChoice.aac128,
        fps: 30,
      ),
    );
  }
  return presets;
}

/// Short-side options offered in the advanced converter.
List<int> resolutionChoices(MediaProbe probe) => [
  for (final s in const [2160, 1440, 1080, 720, 540, 480, 360, 240])
    if (s <= probe.shortSide) s,
];
