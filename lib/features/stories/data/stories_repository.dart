import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../core/media/ffmpeg_service.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../core/tdlib/td_client.dart';
import '../../../core/tdlib/td_errors.dart';
import '../domain/story_feed.dart';

/// Who can see a posted story.
enum StoryAudience {
  everyone('Everyone', td.StoryPrivacySettingsEveryone(exceptUserIds: [])),
  contacts('Contacts', td.StoryPrivacySettingsContacts(exceptUserIds: [])),
  closeFriends('Close friends', td.StoryPrivacySettingsCloseFriends());

  const StoryAudience(this.label, this.privacy);
  final String label;
  final td.StoryPrivacySettings privacy;
}

/// Projection of TDLib's active stories plus the story actions.
///
/// Listened to through [ChangeNotifier]; the chat list asks [of] for the
/// halo and the viewer loads [story] lazily.
class StoriesRepository extends ChangeNotifier {
  StoriesRepository({required TdClient client, required this._prefs, required this._ffmpeg})
    : _client = client {
    _subscription = client.updates.listen(_apply);
    loadMain().ignore();
  }

  final TdClient _client;
  final AppPreferences _prefs;
  final FfmpegService _ffmpeg;
  late final StreamSubscription<td.Update> _subscription;

  final _active = <int, td.ChatActiveStories>{};
  final _stories = <(int, int), td.Story>{};
  var _loading = false;

  /// Hidden entirely by the user (settings → "Hide stories").
  bool get hidden => _prefs.hideStories;

  td.ChatActiveStories? of(int chatId) {
    final s = _active[chatId];
    return s == null || s.stories.isEmpty ? null : s;
  }

  List<td.ChatActiveStories> get feed => StoryFeed.order(_active.values);

  void _apply(td.Update u) {
    switch (u) {
      case td.UpdateChatActiveStories(:final activeStories):
        _active[activeStories.chatId] = activeStories;
        notifyListeners();
      case td.UpdateStory(:final story):
        _stories[(story.senderChatId, story.id)] = story;
      case td.UpdateStoryDeleted(:final storySenderChatId, :final storyId):
        _stories.remove((storySenderChatId, storyId));
      case td.UpdateAuthorizationState(authorizationState: td.AuthorizationStateReady()):
        loadMain().ignore();
      case td.UpdateAuthorizationState(authorizationState: td.AuthorizationStateClosed()):
        _active.clear();
        _stories.clear();
        notifyListeners();
      default:
    }
  }

  /// Asks TDLib to announce every chat with active stories (it answers with
  /// [td.UpdateChatActiveStories]); 404 means "all loaded".
  Future<void> loadMain() async {
    if (_loading) return;
    _loading = true;
    try {
      for (var i = 0; i < 20; i++) {
        await _client.invoke<td.Ok>(const td.LoadActiveStories(storyList: td.StoryListMain()));
      }
    } on TdException {
      // 404 (done) or not logged in yet.
    } finally {
      _loading = false;
    }
  }

  Future<td.ChatActiveStories> refresh(int chatId) async {
    final s = await _client.invoke<td.ChatActiveStories>(td.GetChatActiveStories(chatId: chatId));
    _active[chatId] = s;
    notifyListeners();
    return s;
  }

  Future<td.Story> story(int chatId, int storyId) async {
    final cached = _stories[(chatId, storyId)];
    if (cached != null) return cached;
    final s = await _client.invoke<td.Story>(
      td.GetStory(storySenderChatId: chatId, storyId: storyId, onlyLocal: false),
    );
    return _stories[(chatId, storyId)] = s;
  }

  /// Marks the story as viewed, unless the user hides story views (ghost mode).
  Future<void> open(int chatId, int storyId) async {
    if (_prefs.hideStoryViews) return;
    await _client.invoke<td.Ok>(td.OpenStory(storySenderChatId: chatId, storyId: storyId));
  }

  Future<void> close(int chatId, int storyId) async {
    if (_prefs.hideStoryViews) return;
    await _client.invoke<td.Ok>(td.CloseStory(storySenderChatId: chatId, storyId: storyId));
  }

  Future<void> react(int chatId, int storyId, String? emoji) => _client.invoke<td.Ok>(
    td.SetStoryReaction(
      storySenderChatId: chatId,
      storyId: storyId,
      reactionType: emoji == null ? null : td.ReactionTypeEmoji(emoji: emoji),
      updateRecentReactions: true,
    ),
  );

  Future<void> reply(int chatId, int storyId, String text) => _client.invoke<td.Message>(
    td.SendMessage(
      chatId: chatId,
      messageThreadId: 0,
      replyTo: td.InputMessageReplyToStory(storySenderChatId: chatId, storyId: storyId),
      inputMessageContent: td.InputMessageText(
        text: td.FormattedText(text: text, entities: const []),
        clearDraft: false,
      ),
    ),
  );

  /// Who viewed, reacted to or reposted a story the user (or a channel they
  /// administer, [asChat]) posted. Page with [StoryInteractions.nextOffset].
  Future<td.StoryInteractions> interactions(
    td.Story story, {
    required bool asChat,
    String query = '',
    bool onlyContacts = false,
    bool reactionsFirst = false,
    String offset = '',
    int limit = 50,
  }) => _client.invoke<td.StoryInteractions>(
    asChat
        ? td.GetChatStoryInteractions(
            storySenderChatId: story.senderChatId,
            storyId: story.id,
            preferForwards: false,
            offset: offset,
            limit: limit,
          )
        : td.GetStoryInteractions(
            storyId: story.id,
            query: query,
            onlyContacts: onlyContacts,
            preferForwards: false,
            preferWithReaction: reactionsFirst,
            offset: offset,
            limit: limit,
          ),
  );

  /// Channels and supergroups the user may post stories to (besides
  /// themselves). Each must still pass [cannotPost].
  Future<List<int>> postTargets() async {
    try {
      return (await _client.invoke<td.Chats>(const td.GetChatsToSendStories())).chatIds;
    } on TdException {
      return const [];
    }
  }

  /// Why [chatId] can't post a story right now, or null when it can.
  Future<String?> cannotPost(int chatId) async {
    try {
      final r = await _client.invoke<td.CanSendStoryResult>(td.CanSendStory(chatId: chatId));
      return switch (r) {
        td.CanSendStoryResultOk() => null,
        td.CanSendStoryResultPremiumNeeded() => 'Posting stories needs Telegram Premium on this account.',
        td.CanSendStoryResultBoostNeeded() => 'This channel needs more boosts to post stories.',
        td.CanSendStoryResultActiveStoryLimitExceeded() => 'You have reached the limit of active stories.',
        td.CanSendStoryResultWeeklyLimitExceeded(:final retryAfter) =>
          'Weekly story limit reached. Try again in ${(retryAfter / 3600).ceil()} h.',
        td.CanSendStoryResultMonthlyLimitExceeded(:final retryAfter) =>
          'Monthly story limit reached. Try again in ${(retryAfter / 86400).ceil()} days.',
      };
    } on TdException catch (e) {
      return e.message;
    }
  }

  /// Converts [path] to story format and posts it as [chatId] (the user's
  /// Saved Messages chat posts on their own behalf). Returns an error text.
  Future<String?> post({
    required int chatId,
    required String path,
    required bool isVideo,
    String caption = '',
    StoryAudience audience = StoryAudience.everyone,
    bool keepOnProfile = false,
    bool protect = false,
    List<td.InputStoryArea> areas = const [],
    String? overlayPng,
    void Function(double)? onProgress,
  }) async {
    final td.InputStoryContent content;
    if (isVideo) {
      final probe = await _ffmpeg.probe(path);
      if (probe == null) return 'Could not read this video.';
      final out = await _ffmpeg.tempPath('mp4');
      final duration = probe.duration > StoryMedia.maxVideo ? StoryMedia.maxVideo : probe.duration;
      var ok = await _ffmpeg.run(
        StoryMedia.videoArgs(path, out, hasAudio: probe.hasAudio, overlay: overlayPng),
        duration: duration,
        onProgress: onProgress,
      );
      ok =
          ok ||
          await _ffmpeg.run(
            StoryMedia.videoArgs(path, out, hasAudio: probe.hasAudio, encoder: 'mpeg4', overlay: overlayPng),
            duration: duration,
            onProgress: onProgress,
          );
      if (!ok) return 'Could not convert this video for stories.';
      content = td.InputStoryContentVideo(
        video: td.InputFileLocal(path: out),
        addedStickerFileIds: const [],
        duration: duration.inMilliseconds / 1000,
        coverFrameTimestamp: 0,
        isAnimation: false,
      );
    } else {
      final out = await _ffmpeg.tempPath('jpg');
      final ok = await _ffmpeg.run(StoryMedia.photoArgs(path, out, overlay: overlayPng));
      content = td.InputStoryContentPhoto(
        photo: td.InputFileLocal(path: ok ? out : path),
        addedStickerFileIds: const [],
      );
    }
    try {
      await _client.invoke<td.Story>(
        td.SendStory(
          chatId: chatId,
          content: content,
          areas: areas.isEmpty ? null : td.InputStoryAreas(areas: areas),
          caption: caption.isEmpty ? null : td.FormattedText(text: caption, entities: const []),
          privacySettings: audience.privacy,
          activePeriod: 86400,
          isPostedToChatPage: keepOnProfile,
          protectContent: protect,
        ),
      );
      return null;
    } on TdException catch (e) {
      return e.message;
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
