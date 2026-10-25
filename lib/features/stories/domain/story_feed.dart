import 'package:handy_tdlib_next/api.dart' as td;

/// Pure helpers over TDLib's active-story lists.
abstract final class StoryFeed {
  /// Stories the user hasn't opened yet.
  static bool hasUnseen(td.ChatActiveStories s) => s.stories.any((i) => i.storyId > s.maxReadStoryId);

  /// Where the viewer starts in a chat: the oldest unseen story, or the
  /// first one when everything has been seen.
  static int startIndex(td.ChatActiveStories s) {
    final i = s.stories.indexWhere((i) => i.storyId > s.maxReadStoryId);
    return i < 0 ? 0 : i;
  }

  /// The main feed in TDLib's order (unseen first, then most recent),
  /// skipping archived and empty entries.
  static List<td.ChatActiveStories> order(Iterable<td.ChatActiveStories> all) =>
      all.where((s) => s.list is td.StoryListMain && s.stories.isNotEmpty && s.order != 0).toList()
        ..sort((a, b) => b.order.compareTo(a.order));
}

/// The ffmpeg arguments that turn picked media into what Telegram stories
/// accept: 1080×1920 photos and 720×1280 H.264 video at most 60 s long,
/// letterboxed rather than cropped so nothing the user framed is lost.
abstract final class StoryMedia {
  static const maxVideo = Duration(seconds: 60);

  static String _fit(int w, int h) =>
      'scale=$w:$h:force_original_aspect_ratio=decrease,pad=$w:$h:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1';

  static List<String> photoArgs(String input, String output) => [
    '-i',
    input,
    '-vf',
    _fit(1080, 1920),
    '-frames:v',
    '1',
    '-q:v',
    '3',
    output,
  ];

  static List<String> videoArgs(
    String input,
    String output, {
    required bool hasAudio,
    String encoder = 'h264_mediacodec',
  }) => [
    '-i',
    input,
    '-t',
    '${maxVideo.inSeconds}',
    '-map',
    '0:v:0',
    if (hasAudio) ...['-map', '0:a:0?'],
    '-vf',
    '${_fit(720, 1280)},fps=30,format=yuv420p',
    '-c:v',
    encoder,
    '-b:v',
    '2500k',
    // A key frame every second, as Telegram asks for story video.
    '-g',
    '30',
    if (encoder == 'mpeg4') ...['-qscale:v', '4'] else ...['-profile:v', 'main'],
    if (hasAudio) ...['-c:a', 'aac', '-b:a', '128k', '-ac', '2'] else '-an',
    '-movflags',
    '+faststart',
    output,
  ];
}
