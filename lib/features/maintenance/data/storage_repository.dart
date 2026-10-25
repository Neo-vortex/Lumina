import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/media/ffmpeg_service.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../core/tdlib/td_client.dart';

/// What the user can clear separately.
enum CacheKind {
  photos('Photos', [
    td.FileTypePhoto(),
    td.FileTypeThumbnail(),
    td.FileTypeProfilePhoto(),
    td.FileTypeWallpaper(),
  ]),
  videos('Videos & GIFs', [td.FileTypeVideo(), td.FileTypeAnimation(), td.FileTypeVideoNote()]),
  voice('Voice & music', [td.FileTypeVoiceNote(), td.FileTypeAudio()]),
  stories('Stories', [td.FileTypePhotoStory(), td.FileTypeVideoStory()]),
  files('Files', [td.FileTypeDocument()]),
  stickers('Stickers', [td.FileTypeSticker()]),
  other('Other', [td.FileTypeUnknown(), td.FileTypeNone(), td.FileTypeNotificationSound()]);

  const CacheKind(this.label, this.types);
  final String label;
  final List<td.FileType> types;

  static CacheKind of(td.FileType t) =>
      values.firstWhere((k) => k.types.any((x) => x.runtimeType == t.runtimeType), orElse: () => other);
}

class StorageUsage {
  const StorageUsage({required this.total, required this.byKind, required this.databaseBytes});

  final int total;
  final Map<CacheKind, int> byKind;
  final int databaseBytes;

  /// Groups TDLib's per-chat, per-type statistics by [CacheKind]. Secret
  /// chat files are never listed: TDLib keeps them out of the cache.
  factory StorageUsage.from(td.StorageStatistics s, {int databaseBytes = 0}) {
    final byKind = <CacheKind, int>{};
    for (final chat in s.byChat) {
      for (final t in chat.byFileType) {
        final k = CacheKind.of(t.fileType);
        byKind[k] = (byKind[k] ?? 0) + t.size;
      }
    }
    // With chatLimit 0 every chat is folded into one chat_id 0 entry.
    return StorageUsage(total: s.size, byKind: byKind, databaseBytes: databaseBytes);
  }
}

/// TDLib file cache: usage, manual clearing and the "keep media" policy.
class StorageRepository {
  StorageRepository({required this._client, required this._prefs, required this._ffmpeg});

  final TdClient _client;
  final AppPreferences _prefs;
  final FfmpegService _ffmpeg;

  Future<StorageUsage> usage() async {
    final fast = await _client.invoke<td.StorageStatisticsFast>(const td.GetStorageStatisticsFast());
    final full = await _client.invoke<td.StorageStatistics>(const td.GetStorageStatistics(chatLimit: 0));
    return StorageUsage.from(full, databaseBytes: fast.databaseSize + fast.languagePackDatabaseSize);
  }

  /// Deletes cached files of [kinds] (all kinds when null). Files TDLib is
  /// using right now are kept by TDLib itself.
  Future<void> clear({Set<CacheKind>? kinds}) async {
    await _client.invoke<td.StorageStatistics>(
      td.OptimizeStorage(
        size: 0,
        ttl: 0,
        count: 0,
        immunityDelay: 0,
        fileTypes: [for (final k in kinds ?? CacheKind.values.toSet()) ...k.types],
        chatIds: const [],
        excludeChatIds: const [],
        returnDeletedFileStatistics: false,
        chatLimit: 0,
      ),
    );
    if (kinds == null) await _ffmpeg.purgeTemp(age: Duration.zero);
  }

  /// Applies the user's "keep media" period; run once per session.
  Future<void> autoClean() async {
    final days = _prefs.keepMediaDays;
    if (days <= 0) return;
    await _client.invoke<td.StorageStatistics>(
      td.OptimizeStorage(
        size: -1,
        ttl: days * 86400,
        count: -1,
        immunityDelay: -1,
        fileTypes: const [],
        chatIds: const [],
        excludeChatIds: const [],
        returnDeletedFileStatistics: false,
        chatLimit: 0,
      ),
    );
  }
}
