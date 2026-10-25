import 'package:handy_tdlib_next/api.dart' as td;

import '../../../core/media/ffmpeg_service.dart';
import 'video_presets.dart';

/// A file the user picked, with what we know about it.
class PickedMedia {
  PickedMedia({required this.path, required this.kind, this.probe});

  final String path;
  final MediaKind kind;
  MediaProbe? probe;

  /// Chosen conversion for videos (null = original).
  VideoPreset? preset;

  /// Path actually sent (converted output, or [path]).
  String? sendPath;

  String get name => path.split('/').last;
}

enum MediaKind { photo, video, file }

MediaKind kindForPath(String path) {
  final ext = path.split('.').last.toLowerCase();
  const photos = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'bmp'};
  const videos = {'mp4', 'mov', 'mkv', 'webm', '3gp', 'm4v', 'avi', 'ts'};
  if (photos.contains(ext)) return MediaKind.photo;
  if (videos.contains(ext)) return MediaKind.video;
  return MediaKind.file;
}

/// Turns picked files into TDLib input content, converting videos first.
class MediaSender {
  MediaSender(this._ffmpeg);

  final FfmpegService _ffmpeg;

  FfmpegService get ffmpeg => _ffmpeg;

  Future<PickedMedia> inspect(String path) async {
    final kind = kindForPath(path);
    final media = PickedMedia(path: path, kind: kind);
    if (kind != MediaKind.file) media.probe = await _ffmpeg.probe(path);
    return media;
  }

  /// Runs the chosen preset; returns the output path (or the original).
  Future<String?> prepare(
    PickedMedia media, {
    void Function(double)? onProgress,
    FfmpegCancelToken? cancel,
  }) async {
    final preset = media.preset;
    final probe = media.probe;
    if (media.kind != MediaKind.video || preset == null || preset.isOriginal || probe == null) {
      return media.sendPath = media.path;
    }
    final out = await _ffmpeg.tempPath(preset.codec!.container);
    var ok = await _ffmpeg.run(
      preset.ffmpegArgs(probe, media.path, out),
      duration: probe.duration,
      onProgress: onProgress,
      cancel: cancel,
    );
    // Some devices lack the hardware encoder or reject its input format;
    // MPEG-4 Part 2 is always available as a last resort.
    if (!ok && !(cancel?.isCancelled ?? false) && preset.codec != VideoCodec.mpeg4) {
      final fallback = VideoPreset(
        id: '${preset.id}-fallback',
        title: preset.title,
        description: preset.description,
        codec: VideoCodec.mpeg4,
        shortSide: preset.shortSide,
        videoKbps: (preset.videoKbps * 1.4).round(),
        audio: preset.audio,
        fps: preset.fps,
      );
      ok = await _ffmpeg.run(
        fallback.ffmpegArgs(probe, media.path, out),
        duration: probe.duration,
        onProgress: onProgress,
        cancel: cancel,
      );
    }
    return ok ? media.sendPath = out : null;
  }

  Future<td.InputMessageContent> build(
    PickedMedia media, {
    required td.FormattedText? caption,
    bool asFile = false,
    bool spoiler = false,
    bool viewOnce = false,
  }) async {
    final path = media.sendPath ?? media.path;
    final selfDestruct = viewOnce ? const td.MessageSelfDestructTypeImmediately() : null;
    if (asFile || media.kind == MediaKind.file) {
      return td.InputMessageDocument(
        document: td.InputFileLocal(path: path),
        disableContentTypeDetection: asFile,
        caption: caption,
      );
    }
    final probe = media.kind == MediaKind.video && path != media.path
        ? await _ffmpeg.probe(path)
        : media.probe;
    if (media.kind == MediaKind.photo) {
      return td.InputMessagePhoto(
        photo: td.InputFileLocal(path: path),
        addedStickerFileIds: const [],
        width: probe?.width ?? 0,
        height: probe?.height ?? 0,
        caption: caption,
        showCaptionAboveMedia: false,
        selfDestructType: selfDestruct,
        hasSpoiler: spoiler,
      );
    }
    final thumb = await _ffmpeg.thumbnail(path);
    final thumbProbe = thumb == null ? null : await _ffmpeg.probe(thumb);
    return td.InputMessageVideo(
      video: td.InputFileLocal(path: path),
      thumbnail: thumb == null
          ? null
          : td.InputThumbnail(
              thumbnail: td.InputFileLocal(path: thumb),
              width: thumbProbe?.width ?? 0,
              height: thumbProbe?.height ?? 0,
            ),
      addedStickerFileIds: const [],
      duration: probe?.duration.inSeconds ?? 0,
      width: probe?.width ?? 0,
      height: probe?.height ?? 0,
      supportsStreaming: path.endsWith('.mp4'),
      caption: caption,
      showCaptionAboveMedia: false,
      selfDestructType: selfDestruct,
      hasSpoiler: spoiler,
    );
  }
}
