import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:lumina/core/media/ffmpeg_service.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/stories/data/saved_stories_store.dart';
import 'package:lumina/features/stories/data/stories_repository.dart';
import 'package:lumina/features/stories/domain/story_decoration.dart';
import 'package:lumina/features/stories/domain/story_feed.dart';

import '../../helpers/fakes.dart';

td.File _file(int id, String path) => td.File(
  id: id,
  size: 10,
  expectedSize: 10,
  local: td.LocalFile(
    path: path,
    canBeDownloaded: true,
    canBeDeleted: true,
    isDownloadingActive: false,
    isDownloadingCompleted: true,
    downloadOffset: 0,
    downloadedPrefixSize: 10,
    downloadedSize: 10,
  ),
  remote: const td.RemoteFile(
    id: 'r',
    uniqueId: 'u',
    isUploadingActive: false,
    isUploadingCompleted: true,
    uploadedSize: 10,
  ),
);

td.Story _story(int id, {required String path, bool canBeForwarded = true}) => td.Story(
  id: id,
  posterChatId: 42,
  date: 1760000000,
  isBeingPosted: false,
  isBeingEdited: false,
  isEdited: false,
  isPostedToChatPage: false,
  isVisibleOnlyForSelf: false,
  canBeAddedToAlbum: false,
  canBeDeleted: false,
  canBeEdited: false,
  canBeForwarded: canBeForwarded,
  canBeReplied: true,
  canSetPrivacySettings: false,
  canToggleIsPostedToChatPage: false,
  canGetStatistics: false,
  canGetInteractions: false,
  hasExpiredViewers: false,
  privacySettings: const td.StoryPrivacySettingsEveryone(exceptUserIds: []),
  content: td.StoryContentPhoto(
    photo: td.Photo(
      hasStickers: false,
      sizes: [
        td.PhotoSize(type: 'y', photo: _file(5, path), width: 1080, height: 1920, progressiveSizes: const []),
      ],
    ),
  ),
  areas: const [],
  caption: const td.FormattedText(text: 'sunset', entities: []),
  albumIds: const [],
);

void main() {
  group('decorations', () {
    test('reaction tags become suggested-reaction areas, not burned in', () {
      final r = ReactionTag('🔥')..center = const Offset(0.25, 0.75);
      expect(r.burned, isFalse);
      final area = DecorationPainter.areaOf(r)!;
      expect(area.type, isA<td.InputStoryAreaTypeSuggestedReaction>());
      expect(area.position.xPercentage, closeTo(25, 1e-9));
      expect(area.position.yPercentage, closeTo(75, 1e-9));
      // A circle: same pixel width and height on the 9:16 frame.
      expect(area.position.widthPercentage * 1080, closeTo(area.position.heightPercentage * 1920, 1e-6));
    });

    test('links and places are burned in and tappable; plain stickers have no area', () {
      expect(LinkTag('https://www.example.org/x').label, 'example.org');
      expect(
        DecorationPainter.areaOf(LinkTag('https://example.org'))!.type,
        isA<td.InputStoryAreaTypeLink>(),
      );
      final place = LocationTag('Old Town', latitude: 1, longitude: 2);
      expect(place.burned, isTrue);
      expect(DecorationPainter.areaOf(place)!.type, isA<td.InputStoryAreaTypeLocation>());
      expect(DecorationPainter.areaOf(EmojiSticker('🌸')), isNull);
      expect(DecorationPainter.areaOf(TextSticker('hi')), isNull);
    });

    test('rotation is reported in degrees within 0..360', () {
      final t = LinkTag('https://a.b')..rotation = -3.14159265 / 2;
      expect(DecorationPainter.areaOf(t)!.position.rotationAngle, closeTo(270, 1e-4));
    });

    test('sizes scale with the frame so preview and overlay match', () {
      final d = TextSticker('Hello')..scale = 1.5;
      final small = DecorationPainter.sizeOf(d, const Size(360, 640));
      final big = DecorationPainter.sizeOf(d, const Size(1080, 1920));
      expect(big.width / small.width, closeTo(3, 0.15));
    });
  });

  test('overlay is composited over the letterboxed frame', () {
    final v = StoryMedia.videoArgs('in.mp4', 'out.mp4', hasAudio: true, overlay: 'o.png').join(' ');
    expect(v, contains('-loop 1 -i o.png'));
    expect(v, contains('[b][o]overlay=0:0'));
    expect(v, contains('-map [v]'));
    expect(v, contains('-shortest'));
    final p = StoryMedia.photoArgs('a.jpg', 'b.jpg', overlay: 'o.png').join(' ');
    expect(p, contains('[1:v]scale=1080:1920[o]'));
  });

  group('SavedStoriesStore', () {
    late Directory tmp;
    late FakeTdClient client;
    late SavedStoriesStore store;
    late String media;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('saved');
      media = '${tmp.path}/src.jpg';
      await File(media).writeAsBytes(List.filled(10, 7));
      client = FakeTdClient()
        ..respond = (f) => switch (f) {
          td.DownloadFile() => _file(5, media),
          td.LoadActiveStories() => const td.TdError(code: 404, message: 'done'),
          _ => const td.Ok(),
        };
      store = _store(client, tmp);
    });

    tearDown(() async {
      store.dispose();
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('saves a copy, survives a restart, and refuses protected stories', () async {
      expect(await store.save(_story(1, path: media), chatTitle: 'Ana'), SaveResult.saved);
      expect(await store.save(_story(1, path: media), chatTitle: 'Ana'), SaveResult.alreadySaved);
      expect(
        await store.save(_story(2, path: media, canBeForwarded: false), chatTitle: 'Ana'),
        SaveResult.protected,
      );
      expect(File(store.pathOf('42/1.jpg')).existsSync(), isTrue);

      final again = _store(client, tmp);
      await again.ready();
      expect(again.forChat(42).single.caption, 'sunset');
      expect(again.posters.single.title, 'Ana');
      again.dispose();
    });

    test('auto-save keeps new active stories; logout wipes the history', () async {
      await store.setAutoSave(42, true);
      client.respond = (f) => switch (f) {
        td.GetStory(:final storyId) => _story(storyId, path: media),
        td.DownloadFile() => _file(5, media),
        _ => const td.Ok(),
      };
      client.emitUpdate(
        const td.UpdateChatActiveStories(
          activeStories: td.ChatActiveStories(
            chatId: 42,
            list: td.StoryListMain(),
            order: 1,
            canBeArchived: false,
            maxReadStoryId: 0,
            stories: [td.StoryInfo(storyId: 9, date: 0, isForCloseFriends: false, isLive: false)],
          ),
        ),
      );
      for (var i = 0; i < 50 && !store.isSaved(42, 9); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(store.forChat(42).single.auto, isTrue);
      expect(client.sentOf<td.OpenStory>(), isEmpty, reason: 'auto-save must not mark stories viewed');

      client.emit(const td.AuthorizationStateClosed());
      for (var i = 0; i < 50 && await Directory('${tmp.path}/vault').exists(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(store.posters, isEmpty);
      expect(await Directory('${tmp.path}/vault').exists(), isFalse);
    });
  });
}

SavedStoriesStore _store(FakeTdClient client, Directory tmp) {
  final prefs = AppPreferences.inMemory();
  final ffmpeg = FfmpegService();
  return SavedStoriesStore(
    client: client,
    stories: StoriesRepository(client: client, prefs: prefs, ffmpeg: ffmpeg),
    cache: TelegramCache.detached(),
    files: FileStore(client),
    ffmpeg: ffmpeg,
    root: () async => Directory('${tmp.path}/vault'),
  );
}
