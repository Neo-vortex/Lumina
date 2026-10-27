import 'package:lumina_tdlib/api.dart' as td;

enum DownloadFilter {
  all('All'),
  videos('Videos'),
  files('Files'),
  music('Music'),
  photos('Photos');

  const DownloadFilter(this.label);
  final String label;
}

/// One entry of TDLib's download list, with the file's latest state.
class DownloadItem {
  const DownloadItem({
    required this.fileId,
    required this.message,
    required this.addDate,
    required this.completeDate,
    required this.isPaused,
    this.file,
  });

  factory DownloadItem.of(td.FileDownload d) => DownloadItem(
    fileId: d.fileId,
    message: d.message,
    addDate: d.addDate,
    completeDate: d.completeDate,
    isPaused: d.isPaused,
  );

  final int fileId;
  final td.Message message;
  final int addDate;
  final int completeDate;
  final bool isPaused;
  final td.File? file;

  bool get isCompleted => completeDate != 0;

  DownloadFilter get kind => switch (message.content) {
    td.MessageVideo() || td.MessageVideoNote() || td.MessageAnimation() => DownloadFilter.videos,
    td.MessageAudio() || td.MessageVoiceNote() => DownloadFilter.music,
    td.MessagePhoto() => DownloadFilter.photos,
    _ => DownloadFilter.files,
  };

  String get name => switch (message.content) {
    td.MessageDocument(:final document) => document.fileName,
    td.MessageAudio(:final audio) => audio.fileName.isEmpty ? audio.title : audio.fileName,
    td.MessageVideo(:final video) => video.fileName.isEmpty ? 'Video' : video.fileName,
    td.MessageAnimation(:final animation) => animation.fileName.isEmpty ? 'GIF' : animation.fileName,
    td.MessagePhoto() => 'Photo',
    td.MessageVoiceNote() => 'Voice message',
    td.MessageVideoNote() => 'Video message',
    _ => 'File',
  };

  int get size {
    final f = file;
    if (f == null) return 0;
    return f.size > 0 ? f.size : f.expectedSize;
  }

  int get downloaded => file?.local.downloadedSize ?? 0;

  DownloadItem copyWith({int? completeDate, bool? isPaused, td.File? file}) => DownloadItem(
    fileId: fileId,
    message: message,
    addDate: addDate,
    completeDate: completeDate ?? this.completeDate,
    isPaused: isPaused ?? this.isPaused,
    file: file ?? this.file,
  );
}
