import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib_next/api.dart' as td;
import 'package:lumina/core/media/ffmpeg_service.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/stories/data/stories_repository.dart';
import 'package:lumina/features/stories/domain/story_feed.dart';

import '../../helpers/fakes.dart';

td.ChatActiveStories _active(int chatId, List<int> ids, {int read = 0, int order = 1, td.StoryList? list}) =>
    td.ChatActiveStories(
      chatId: chatId,
      list: list ?? const td.StoryListMain(),
      order: order,
      maxReadStoryId: read,
      stories: [for (final id in ids) td.StoryInfo(storyId: id, date: 0, isForCloseFriends: false)],
    );

void main() {
  group('StoryFeed', () {
    test('unseen and start index follow maxReadStoryId', () {
      final s = _active(1, [10, 11, 12], read: 10);
      expect(StoryFeed.hasUnseen(s), isTrue);
      expect(StoryFeed.startIndex(s), 1);
      final seen = _active(1, [10, 11], read: 11);
      expect(StoryFeed.hasUnseen(seen), isFalse);
      expect(StoryFeed.startIndex(seen), 0);
    });

    test('feed keeps the main list in TDLib order', () {
      final feed = StoryFeed.order([
        _active(1, [1], order: 5),
        _active(2, [1], order: 9),
        _active(3, [1], order: 7, list: const td.StoryListArchive()),
        _active(4, [], order: 8),
        _active(5, [1], order: 0),
      ]);
      expect([for (final s in feed) s.chatId], [2, 1]);
    });
  });

  group('StoryMedia', () {
    test('video is letterboxed to 720x1280, capped at 60 s, key frame each second', () {
      final args = StoryMedia.videoArgs('in.mov', 'out.mp4', hasAudio: false);
      expect(args, containsAllInOrder(['-t', '60']));
      expect(args.join(' '), contains('scale=720:1280:force_original_aspect_ratio=decrease'));
      expect(args, containsAllInOrder(['-g', '30']));
      expect(args, contains('-an'));
      expect(args.last, 'out.mp4');
    });

    test('photo is fitted to 1080x1920', () {
      expect(StoryMedia.photoArgs('a.jpg', 'b.jpg').join(' '), contains('pad=1080:1920'));
    });
  });

  group('StoriesRepository', () {
    late FakeTdClient client;
    late AppPreferences prefs;
    late StoriesRepository repo;

    setUp(() {
      client = FakeTdClient();
      client.respond = (f) => switch (f) {
        td.LoadActiveStories() => const td.TdError(code: 404, message: 'Not Found'),
        _ => const td.Ok(),
      };
      prefs = AppPreferences.inMemory();
      repo = StoriesRepository(client: client, prefs: prefs, ffmpeg: FfmpegService());
    });

    tearDown(() => repo.dispose());

    test('projects UpdateChatActiveStories', () async {
      var notified = 0;
      repo.addListener(() => notified++);
      client.emitUpdate(td.UpdateChatActiveStories(activeStories: _active(7, [1, 2])));
      await Future<void>.delayed(Duration.zero);
      expect(repo.of(7)?.stories, hasLength(2));
      expect(notified, 1);
      client.emitUpdate(td.UpdateChatActiveStories(activeStories: _active(7, [])));
      await Future<void>.delayed(Duration.zero);
      expect(repo.of(7), isNull);
    });

    test('hiding story views never marks a story as viewed', () async {
      prefs.hideStoryViews = true;
      await repo.open(7, 1);
      await repo.close(7, 1);
      expect(client.sentOf<td.OpenStory>(), isEmpty);
      prefs.hideStoryViews = false;
      await repo.open(7, 1);
      expect(client.sentOf<td.OpenStory>(), hasLength(1));
    });

    test('replies go to the poster as a reply to the story', () async {
      client.respond = (f) => fakeMessage(1, chatId: 7);
      await repo.reply(7, 3, 'nice');
      final send = client.sentOf<td.SendMessage>().single;
      expect(send.chatId, 7);
      expect(send.replyTo, isA<td.InputMessageReplyToStory>());
    });
  });
}
