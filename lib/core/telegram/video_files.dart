import 'package:lumina_tdlib/api.dart' as td;

import '../storage/app_preferences.dart';

/// Which file a video message plays and downloads. Telegram stores lower
/// resolution encodes beside big uploads (`alternativeVideos`); the official
/// apps show and fetch one of those, which is why a clip can read 5.8 MB
/// there and 35 MB as the original.
abstract final class VideoFiles {
  /// Auto takes the best copy up to this height.
  static const autoMaxHeight = 720;

  static VideoQuality get preferred => AppPreferences.current?.videoQuality ?? VideoQuality.low;

  /// The file for [content] in [quality] (the preference when null).
  static td.File pick(td.MessageVideo content, [VideoQuality? quality]) =>
      alternative(content, quality ?? preferred)?.video ?? content.video.video;

  /// The encode [quality] picks, or null for the original upload.
  static td.AlternativeVideo? alternative(td.MessageVideo content, VideoQuality quality) {
    final alts = [
      for (final a in content.alternativeVideos)
        if (a.height > 0 && a.video.id != content.video.video.id) a,
    ];
    if (alts.isEmpty || quality == VideoQuality.original) return null;
    // Smaller first; at equal height H.264 (decodes everywhere in hardware).
    int h264(td.AlternativeVideo a) => a.codec.toLowerCase().contains('264') || a.codec == 'avc' ? 0 : 1;
    alts.sort((a, b) {
      final byHeight = a.height.compareTo(b.height);
      return byHeight != 0 ? byHeight : h264(a).compareTo(h264(b));
    });
    final originalHeight = content.video.height;
    final td.AlternativeVideo pick;
    switch (quality) {
      case VideoQuality.low:
        pick = alts.first;
      case VideoQuality.auto:
        final fits = alts.where((a) => a.height <= autoMaxHeight).toList();
        pick = fits.isEmpty ? alts.first : fits.reduce((a, b) => b.height > a.height ? b : a);
      case VideoQuality.original:
        return null;
    }
    // Never "lower" quality that is the original's size or bigger.
    final size = _size(pick.video), originalSize = _size(content.video.video);
    if (originalHeight > 0 && pick.height >= originalHeight && originalSize > 0 && size >= originalSize) return null;
    return pick;
  }

  /// Every quality this message can play in, for the viewer's picker:
  /// (quality, label such as "480p · 5.8 MB").
  static List<({VideoQuality quality, int height, int size})> options(td.MessageVideo content) {
    final out = <({VideoQuality quality, int height, int size})>[];
    for (final q in VideoQuality.values) {
      final alt = alternative(content, q);
      final file = alt?.video ?? content.video.video;
      out.add((quality: q, height: alt?.height ?? content.video.height, size: _size(file)));
    }
    return out;
  }

  static int _size(td.File f) => f.size > 0 ? f.size : f.expectedSize;
}
