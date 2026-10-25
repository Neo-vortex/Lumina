import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib_next/api.dart' as td;
import 'package:lumina/core/media/ffmpeg_service.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/maintenance/data/storage_repository.dart';

import '../../helpers/fakes.dart';

void main() {
  test('usage groups file types into kinds', () {
    const stats = td.StorageStatistics(
      size: 600,
      count: 4,
      byChat: [
        td.StorageStatisticsByChat(
          chatId: 0,
          size: 600,
          count: 4,
          byFileType: [
            td.StorageStatisticsByFileType(fileType: td.FileTypePhoto(), size: 100, count: 1),
            td.StorageStatisticsByFileType(fileType: td.FileTypeThumbnail(), size: 50, count: 1),
            td.StorageStatisticsByFileType(fileType: td.FileTypeVideoNote(), size: 400, count: 1),
            td.StorageStatisticsByFileType(fileType: td.FileTypeSecure(), size: 50, count: 1),
          ],
        ),
      ],
    );
    final u = StorageUsage.from(stats);
    expect(u.total, 600);
    expect(u.byKind[CacheKind.photos], 150);
    expect(u.byKind[CacheKind.videos], 400);
    expect(u.byKind[CacheKind.other], 50);
  });

  test('clearing one kind only targets its file types', () async {
    final client = FakeTdClient()..respond = (_) => const td.StorageStatistics(size: 0, count: 0, byChat: []);
    final repo = StorageRepository(client: client, prefs: AppPreferences.inMemory(), ffmpeg: FfmpegService());
    await repo.clear(kinds: {CacheKind.voice});
    final call = client.sentOf<td.OptimizeStorage>().single;
    expect(call.size, 0);
    expect(call.ttl, 0);
    expect(call.fileTypes.map((t) => t.runtimeType), [td.FileTypeVoiceNote, td.FileTypeAudio]);
  });

  test('auto clean uses the keep-media period and is off by default', () async {
    final client = FakeTdClient()..respond = (_) => const td.StorageStatistics(size: 0, count: 0, byChat: []);
    final prefs = AppPreferences.inMemory();
    final repo = StorageRepository(client: client, prefs: prefs, ffmpeg: FfmpegService());
    await repo.autoClean();
    expect(client.sentOf<td.OptimizeStorage>(), isEmpty);
    prefs.keepMediaDays = 7;
    await repo.autoClean();
    expect(client.sentOf<td.OptimizeStorage>().single.ttl, 7 * 86400);
  });
}
