/// A story copied into the user's on-device history.
class SavedStory {
  const SavedStory({
    required this.chatId,
    required this.storyId,
    required this.postedAt,
    required this.savedAt,
    required this.isVideo,
    required this.file,
    required this.thumb,
    this.duration = 0,
    this.caption = '',
    this.chatTitle = '',
    this.auto = false,
  });

  final int chatId;
  final int storyId;

  /// Unix seconds.
  final int postedAt;
  final int savedAt;
  final bool isVideo;
  final double duration;

  /// Paths relative to the history folder.
  final String file;
  final String thumb;
  final String caption;

  /// The poster's name when saved, for after the chat is gone.
  final String chatTitle;

  /// Saved by "auto-save", not by hand.
  final bool auto;

  DateTime get posted => DateTime.fromMillisecondsSinceEpoch(postedAt * 1000);
  DateTime get saved => DateTime.fromMillisecondsSinceEpoch(savedAt * 1000);

  Map<String, Object> toJson() => {
    'chatId': chatId,
    'storyId': storyId,
    'postedAt': postedAt,
    'savedAt': savedAt,
    'isVideo': isVideo,
    'duration': duration,
    'file': file,
    'thumb': thumb,
    'caption': caption,
    'chatTitle': chatTitle,
    'auto': auto,
  };

  factory SavedStory.fromJson(Map<String, dynamic> j) => SavedStory(
    chatId: j['chatId'] as int,
    storyId: j['storyId'] as int,
    postedAt: j['postedAt'] as int,
    savedAt: j['savedAt'] as int,
    isVideo: j['isVideo'] as bool? ?? false,
    duration: (j['duration'] as num?)?.toDouble() ?? 0,
    file: j['file'] as String,
    thumb: j['thumb'] as String? ?? j['file'] as String,
    caption: j['caption'] as String? ?? '',
    chatTitle: j['chatTitle'] as String? ?? '',
    auto: j['auto'] as bool? ?? false,
  );
}
