import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/storage/app_preferences.dart';
import '../../../core/tdlib/td_client.dart';

/// Stickers, GIFs and recent emoji for the composer's media panel.
class MediaPanelRepository {
  MediaPanelRepository({required this._client, required this._prefs});

  final TdClient _client;
  final AppPreferences _prefs;
  int? _gifBot;

  Future<List<td.StickerSetInfo>> installedSets() async => (await _client.invoke<td.StickerSets>(
    const td.GetInstalledStickerSets(stickerType: td.StickerTypeRegular()),
  )).sets;

  Future<List<td.Sticker>> setStickers(int setId) async =>
      (await _client.invoke<td.StickerSet>(td.GetStickerSet(setId: setId))).stickers;

  Future<List<td.Sticker>> recentStickers() async =>
      (await _client.invoke<td.Stickers>(const td.GetRecentStickers(isAttached: false))).stickers;

  Future<List<td.Animation>> savedGifs() async =>
      (await _client.invoke<td.Animations>(const td.GetSavedAnimations())).animations;

  /// GIF search through Telegram's @gif inline bot.
  Future<td.InlineQueryResults> searchGifs(int chatId, String query, {String offset = ''}) async {
    _gifBot ??= (await _client.invoke<td.Chat>(const td.SearchPublicChat(username: 'gif'))).id;
    return _client.invoke<td.InlineQueryResults>(
      td.GetInlineQueryResults(botUserId: _gifBot!, chatId: chatId, query: query, offset: offset),
    );
  }

  Future<void> sendSticker(int chatId, td.Sticker s) => _client.invoke<td.Message>(
    td.SendMessage(
      chatId: chatId,
      inputMessageContent: td.InputMessageSticker(
        sticker: td.InputSticker(
          sticker: td.InputFileId(id: s.sticker.id),
          width: s.width,
          height: s.height,
        ),
        emoji: s.emoji,
      ),
    ),
  );

  Future<void> sendGif(int chatId, td.Animation a) => _client.invoke<td.Message>(
    td.SendMessage(
      chatId: chatId,
      inputMessageContent: td.InputMessageAnimation(
        animation: td.InputAnimation(
          animation: td.InputFileId(id: a.animation.id),
          addedStickerFileIds: const [],
          duration: a.duration,
          width: a.width,
          height: a.height,
        ),
        showCaptionAboveMedia: false,
        hasSpoiler: false,
      ),
    ),
  );

  Future<void> sendInlineResult(int chatId, int queryId, String resultId) => _client.invoke<td.Message>(
    td.SendInlineQueryResultMessage(chatId: chatId, queryId: queryId, resultId: resultId, hideViaBot: true),
  );

  /// Emoji you used, most recent first (kept to 32).
  List<String> get recentEmoji => _prefs.recentEmoji;
  void useEmoji(String e) =>
      _prefs.recentEmoji = [e, ..._prefs.recentEmoji.where((x) => x != e)].take(32).toList();
}
