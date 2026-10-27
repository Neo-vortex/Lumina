import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/auto_download/domain/auto_download_policy.dart';

void main() {
  test('presets are recognised; any change makes it custom', () {
    for (final p in AutoDownloadPreset.values.where((p) => p != AutoDownloadPreset.custom)) {
      expect(AutoDownloadPolicy.of(p).preset, p);
    }
    final edited = AutoDownloadPolicy.of(AutoDownloadPreset.medium)
        .toggled(MediaKind.music, ChatKind.channels);
    expect(edited.preset, AutoDownloadPreset.custom);
  });

  test('off allows nothing, high allows everything up to its limits', () {
    final off = AutoDownloadPolicy.of(AutoDownloadPreset.off);
    final high = AutoDownloadPolicy.of(AutoDownloadPreset.high);
    for (final m in MediaKind.values) {
      for (final c in ChatKind.values) {
        expect(off.allows(m, c, size: 1), isFalse);
        expect(high.allows(m, c, size: 1), isTrue);
      }
    }
    expect(high.allows(MediaKind.videos, ChatKind.groups, size: high.maxVideoSize + 1), isFalse);
    expect(high.allows(MediaKind.files, ChatKind.groups, size: high.maxFileSize + 1), isFalse);
  });

  test('only videos and files are limited by size', () {
    final p = AutoDownloadPolicy.of(AutoDownloadPreset.high).copyWith(maxVideoSize: 1000, maxFileSize: 1000);
    expect(p.allows(MediaKind.photos, ChatKind.private, size: 5000000), isTrue);
    expect(p.allows(MediaKind.videos, ChatKind.private, size: 5000), isFalse);
    expect(p.allows(MediaKind.files, ChatKind.private, size: 999), isTrue);
  });

  test('size stops run 100 KB to 4 GB and snap to the nearest', () {
    expect(AutoDownloadPolicy.sizeStops.first, 100 * 1024);
    expect(AutoDownloadPolicy.sizeStops.last, 4 * 1024 * 1024 * 1024);
    expect(AutoDownloadPolicy.snap(1100 * 1024), 1024 * 1024);
    expect(AutoDownloadPolicy.sizeStops.indexOf(AutoDownloadPolicy.snap(1)), 0);
  });

  test('json round trip', () {
    final p = AutoDownloadPolicy.of(AutoDownloadPreset.low)
        .toggled(MediaKind.gifs, ChatKind.groups)
        .copyWith(maxVideoSize: 5 * 1024 * 1024, preloadLargeVideos: true);
    expect(AutoDownloadPolicy.fromJson(p.toJson()), p);
    expect(AutoDownloadPolicy.fromJson('not json'), isNull);
  });

  test('networks start Medium on mobile, High on Wi-Fi, Low when roaming', () {
    expect(AutoDownloadPolicy.defaultFor(NetworkKind.mobile).preset, AutoDownloadPreset.medium);
    expect(AutoDownloadPolicy.defaultFor(NetworkKind.wifi).preset, AutoDownloadPreset.high);
    expect(AutoDownloadPolicy.defaultFor(NetworkKind.roaming).preset, AutoDownloadPreset.low);
  });
}
