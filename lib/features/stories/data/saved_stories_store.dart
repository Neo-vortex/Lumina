import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:handy_tdlib_next/api.dart' as td;
import 'package:path_provider/path_provider.dart';

import '../../../core/media/ffmpeg_service.dart';
import '../../../core/tdlib/td_client.dart';
import '../../../core/telegram/file_store.dart';
import '../../../core/telegram/telegram_cache.dart';
import '../domain/saved_story.dart';
import 'stories_repository.dart';

enum SaveResult { saved, alreadySaved, protected, unsupported, failed }

/// The user's private story history: copies of other people's stories kept
/// on this device after they expire, grouped per poster.
///
/// Files live in app-private storage and are deleted with everything else
/// on logout. Stories whose poster disabled saving
/// (`story.canBeForwarded == false`, which TDLib documents as "saving must
/// be forbidden") are never stored, manually or automatically.
class SavedStoriesStore extends ChangeNotifier {
  SavedStoriesStore({
    required TdClient client,
    required this._stories,
    required this._cache,
    required this._files,
    required this._ffmpeg,
    Future<Directory> Function()? root,
  }) : _root = root ?? _defaultRoot {
    _subscription = client.updates.listen(_onUpdate);
    // Load early so auto-save sees its chat list before the first update.
    ready().ignore();
  }

  final StoriesRepository _stories;
  final TelegramCache _cache;
  final FileStore _files;
  final FfmpegService _ffmpeg;
  final Future<Directory> Function() _root;
  late final StreamSubscription<td.Update> _subscription;

  static Future<Directory> _defaultRoot() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/saved_stories');

  final _entries = <SavedStory>[];
  final _autoSave = <int>{};
  Future<void>? _loading;
  Future<void> _queue = Future.value();
  Directory? _dir;

  Future<void> ready() => _loading ??= _load();

  Future<void> _load() async {
    final dir = _dir = await _root();
    final index = File('${dir.path}/index.json');
    if (!await index.exists()) return;
    try {
      final json = jsonDecode(await index.readAsString()) as Map<String, dynamic>;
      _entries
        ..clear()
        ..addAll([for (final e in json['stories'] as List) SavedStory.fromJson(e as Map<String, dynamic>)]);
      _autoSave
        ..clear()
        ..addAll([for (final id in json['autoSave'] as List? ?? const []) id as int]);
    } on FormatException {
      // A corrupt index loses the list, not the files; start over.
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final dir = _dir!;
    await dir.create(recursive: true);
    final tmp = File('${dir.path}/index.json.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'stories': [for (final e in _entries) e.toJson()],
        'autoSave': _autoSave.toList(),
      }),
    );
    await tmp.rename('${dir.path}/index.json');
  }

  String pathOf(String relative) => '${_dir!.path}/$relative';

  bool isSaved(int chatId, int storyId) => _entries.any((e) => e.chatId == chatId && e.storyId == storyId);

  /// Newest first.
  List<SavedStory> forChat(int chatId) =>
      _entries.where((e) => e.chatId == chatId).toList()..sort((a, b) => b.postedAt.compareTo(a.postedAt));

  /// One entry per poster, most recently saved first.
  List<({int chatId, String title, int count, SavedStory latest})> get posters {
    final byChat = <int, List<SavedStory>>{};
    for (final e in _entries) {
      (byChat[e.chatId] ??= []).add(e);
    }
    return [
      for (final MapEntry(key: id, value: list) in byChat.entries)
        (
          chatId: id,
          title: list.last.chatTitle,
          count: list.length,
          latest: list.reduce((a, b) => a.postedAt >= b.postedAt ? a : b),
        ),
    ]..sort((a, b) => b.latest.savedAt.compareTo(a.latest.savedAt));
  }

  bool autoSaves(int chatId) => _autoSave.contains(chatId);

  Future<void> setAutoSave(int chatId, bool on) async {
    await ready();
    on ? _autoSave.add(chatId) : _autoSave.remove(chatId);
    await _persist();
    notifyListeners();
    if (on) _saveActive(chatId);
  }

  /// Copies [story]'s media into the history. Serialised so two saves of
  /// the same story can't race.
  Future<SaveResult> save(td.Story story, {required String chatTitle, bool auto = false}) {
    final run = _queue.then((_) => _save(story, chatTitle, auto));
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<SaveResult> _save(td.Story story, String chatTitle, bool auto) async {
    await ready();
    if (isSaved(story.senderChatId, story.id)) return SaveResult.alreadySaved;
    if (!story.canBeForwarded) return SaveResult.protected;
    final (td.File? file, bool isVideo, double duration) = switch (story.content) {
      td.StoryContentPhoto(:final photo) when photo.sizes.isNotEmpty => (
        photo.sizes.reduce((a, b) => a.width >= b.width ? a : b).photo,
        false,
        0.0,
      ),
      td.StoryContentVideo(:final video) => (video.video, true, video.duration),
      _ => (null, false, 0.0),
    };
    if (file == null) return SaveResult.unsupported;
    try {
      final src = await _files.downloadAndWait(file.id, priority: auto ? 2 : 24);
      final folder = Directory('${_dir!.path}/${story.senderChatId}');
      await folder.create(recursive: true);
      final ext = isVideo ? 'mp4' : (src.toLowerCase().endsWith('.png') ? 'png' : 'jpg');
      final name = '${story.senderChatId}/${story.id}.$ext';
      await File(src).copy(pathOf(name));
      var thumb = name;
      if (isVideo) {
        final t = await _ffmpeg.thumbnail(pathOf(name));
        if (t != null) {
          thumb = '${story.senderChatId}/${story.id}_thumb.jpg';
          await File(t).rename(pathOf(thumb)).catchError((_) => File(t).copy(pathOf(thumb)));
        }
      }
      _entries.add(
        SavedStory(
          chatId: story.senderChatId,
          storyId: story.id,
          postedAt: story.date,
          savedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          isVideo: isVideo,
          duration: duration,
          file: name,
          thumb: thumb,
          caption: story.caption.text,
          chatTitle: chatTitle,
          auto: auto,
        ),
      );
      await _persist();
      notifyListeners();
      return SaveResult.saved;
    } catch (_) {
      return SaveResult.failed;
    }
  }

  Future<void> delete(SavedStory entry) async {
    await ready();
    _entries.removeWhere((e) => e.chatId == entry.chatId && e.storyId == entry.storyId);
    for (final f in {entry.file, entry.thumb}) {
      await File(pathOf(f)).delete().catchError((_) => File(''));
    }
    await _persist();
    notifyListeners();
  }

  void _onUpdate(td.Update u) {
    switch (u) {
      case td.UpdateChatActiveStories(:final activeStories) when _autoSave.contains(activeStories.chatId):
        _saveFrom(activeStories);
      case td.UpdateAuthorizationState(authorizationState: td.AuthorizationStateClosed()):
        wipe().ignore();
      default:
    }
  }

  void _saveActive(int chatId) {
    final active = _stories.of(chatId);
    if (active != null) _saveFrom(active);
  }

  /// Background auto-save: fetching a story doesn't mark it viewed.
  void _saveFrom(td.ChatActiveStories active) {
    for (final info in active.stories) {
      if (isSaved(active.chatId, info.storyId)) continue;
      _stories
          .story(active.chatId, info.storyId)
          .then((s) => save(s, chatTitle: _cache.chats[active.chatId]?.title ?? '', auto: true))
          .ignore();
    }
  }

  /// Logout: the history goes with the rest of the account's local data.
  Future<void> wipe() async {
    final dir = _dir ?? await _root();
    _entries.clear();
    _autoSave.clear();
    _loading = null;
    if (await dir.exists()) await dir.delete(recursive: true).catchError((_) => dir);
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
