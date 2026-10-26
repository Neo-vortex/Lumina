import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:lumina/features/media/presentation/widgets/video_player_view.dart';

td.File file({int size = 1000, int offset = 0, int prefix = 0, int downloaded = 0, bool done = false}) =>
    td.File(
      id: 1,
      size: size,
      expectedSize: size,
      local: td.LocalFile(
        path: '',
        canBeDownloaded: true,
        canBeDeleted: false,
        isDownloadingActive: !done,
        isDownloadingCompleted: done,
        downloadOffset: offset,
        downloadedPrefixSize: prefix,
        downloadedSize: downloaded,
      ),
      remote: const td.RemoteFile(
        id: '',
        uniqueId: '',
        isUploadingActive: false,
        isUploadingCompleted: true,
        uploadedSize: 0,
      ),
    );

void main() {
  test('the buffered bar runs to the end of the downloaded range holding the playhead', () {
    final d = StreamDownload.of(file(offset: 0, prefix: 400, downloaded: 400));
    expect(d.downloaded, 0.4);
    expect(d.bufferedAhead(0.1), 0.4);
  });

  test('after a seek past the downloaded part, nothing is buffered ahead yet', () {
    final d = StreamDownload.of(file(offset: 700, prefix: 50, downloaded: 450));
    expect(d.bufferedAhead(0.2), 0.2);
    expect(d.bufferedAhead(0.7), 0.75);
    expect(d.downloaded, 0.45);
  });

  test('a finished download buffers everything', () {
    final d = StreamDownload.of(file(downloaded: 1000, done: true));
    expect(d.complete, isTrue);
    expect(d.bufferedAhead(0.3), 1);
  });
}
