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

enum MediaKind { photo, video, audio, file }

/// [music] is set when the user picked from the Music tile: audio then goes
/// out as a playable track. Audio picked as a plain file stays a document.
MediaKind kindForPath(String path, {bool music = false}) {
  final ext = path.split('.').last.toLowerCase();
  const photos = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'bmp'};
  const videos = {'mp4', 'mov', 'mkv', 'webm', '3gp', 'm4v', 'avi', 'ts'};
  const audio = {'mp3', 'm4a', 'aac', 'ogg', 'oga', 'opus', 'flac', 'wav', 'wma', 'alac', 'aiff'};
  if (photos.contains(ext)) return MediaKind.photo;
  if (videos.contains(ext)) return MediaKind.video;
  if (music && audio.contains(ext)) return MediaKind.audio;
  return MediaKind.file;
}

/// Title for a track without tags: the file name minus its extension.
String trackTitle(PickedMedia media) {
  final tagged = media.probe?.title;
  if (tagged != null) return tagged;
  final name = media.name;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/// Turns picked files into TDLib input content, converting videos first.
class MediaSender {
  MediaSender(this._ffmpeg);

  final FfmpegService _ffmpeg;

  FfmpegService get ffmpeg => _ffmpeg;

  Future<PickedMedia> inspect(String path, {bool music = false}) async {
    final kind = kindForPath(path, music: music);
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
    if (media.kind == MediaKind.audio) {
      return td.InputMessageAudio(
        audio: td.InputFileLocal(path: path),
        duration: media.probe?.duration.inSeconds ?? 0,
        title: _clip(trackTitle(media)),
        performer: _clip(media.probe?.performer ?? ''),
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

  /// TDLib allows 0–64 characters for audio title and performer.
  static String _clip(String s) => s.runes.length <= 64 ? s : String.fromCharCodes(s.runes.take(64));
}
