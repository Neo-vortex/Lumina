import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/media/ffmpeg_service.dart';
import 'package:lumina/features/media/data/video_presets.dart';

MediaProbe probe({
  int w = 1920,
  int h = 1080,
  String codec = 'h264',
  int seconds = 60,
  int bitrate = 12000000,
  String pix = 'yuv420p',
  bool audio = true,
}) => MediaProbe(
  path: '/tmp/in.mp4',
  sizeBytes: bitrate ~/ 8 * seconds,
  duration: Duration(seconds: seconds),
  width: w,
  height: h,
  videoCodec: codec,
  audioCodec: audio ? 'aac' : null,
  bitrate: bitrate,
  pixelFormat: pix,
  frameRate: 60,
  rotation: 0,
);

void main() {
  test('simple mode: original plus two smaller variants for H.264 sources', () {
    final presets = simplePresets(probe());
    expect(presets.map((p) => p.id), ['original', 'reduced-720', 'reduced-480']);
    expect(presets.any((p) => p.id == 'compatible'), isFalse);
  });

  test('HEVC, VP9, AV1 and 10-bit sources get a compatibility option', () {
    for (final c in ['hevc', 'vp9', 'av1']) {
      expect(simplePresets(probe(codec: c)).last.id, 'compatible', reason: c);
    }
    expect(simplePresets(probe(pix: 'yuv420p10le')).last.id, 'compatible');
  });

  test('reduced variants are smaller than the original', () {
    final p = probe();
    final presets = simplePresets(p);
    final original = presets.first.estimateBytes(p);
    for (final preset in presets.skip(1)) {
      expect(preset.estimateBytes(p), lessThan(original), reason: preset.id);
    }
  });

  test('portrait video scales its short side (width)', () {
    final p = probe(w: 1080, h: 1920);
    final args = simplePresets(p)[1].ffmpegArgs(p, 'in', 'out.mp4');
    final vf = args[args.indexOf('-vf') + 1];
    expect(vf, contains("scale='if(gt(iw,ih),-2,720)':'if(gt(iw,ih),720,-2)'"));
    expect(vf, contains('fps=30'));
    expect(vf, endsWith('format=yuv420p'));
  });

  test('H.264 uses the hardware encoder, Main profile and faststart', () {
    final p = probe(codec: 'hevc');
    final args = simplePresets(p).last.ffmpegArgs(p, 'in', 'out.mp4');
    expect(args, containsAllInOrder(['-c:v', 'h264_mediacodec']));
    expect(args, containsAllInOrder(['-profile:v', 'main']));
    expect(args, containsAllInOrder(['-movflags', '+faststart']));
    expect(args.last, 'out.mp4');
  });

  test('silent sources and "no audio" drop the audio stream', () {
    final p = probe(audio: false);
    expect(simplePresets(p)[1].ffmpegArgs(p, 'in', 'out.mp4'), contains('-an'));
    const muted = VideoPreset(
      id: 'x',
      title: 'x',
      description: '',
      codec: VideoCodec.h264,
      videoKbps: 800,
      audio: AudioChoice.none,
    );
    expect(muted.ffmpegArgs(probe(), 'in', 'out.mp4'), contains('-an'));
  });

  test('a small source never upscales', () {
    final p = probe(w: 640, h: 360);
    final args = simplePresets(p)[1].ffmpegArgs(p, 'in', 'out.mp4');
    expect(args[args.indexOf('-vf') + 1], isNot(contains('scale')));
    expect(resolutionChoices(p), [360, 240]);
  });
}
