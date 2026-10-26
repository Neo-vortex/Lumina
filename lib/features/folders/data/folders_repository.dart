import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/storage/app_preferences.dart';
import '../../../core/tdlib/td_client.dart';
import '../../../core/telegram/telegram_cache.dart';
import '../domain/folder_draft.dart';

/// TDLib's chat-folder API (spec: docs/superpowers/specs/2026-10-26-chat-folders-design.md),
/// local folder colours for non-Premium accounts, and the "new chats in a
/// shared folder" checks TDLib leaves to clients.
class FoldersRepository {
  FoldersRepository({
    required this._client,
    required this._cache,
    required this._prefs,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _sub = _client.updates.listen((u) {
      if (u case td.UpdateOption(name: 'is_premium', value: td.OptionValueBoolean(:final value))) {
        _premium = value;
      }
    });
  }

  final TdClient _client;
  final TelegramCache _cache;
  final AppPreferences _prefs;
  final DateTime Function() _now;
  late final StreamSubscription<td.Update> _sub;
  var _premium = false;
  StreamSubscription<CacheEvent>? _foldersSub;

  /// TDLib allows checking a folder's new chats once per period; we use 10 min.
  static const newChatsPeriod = Duration(minutes: 10);
  final _lastChecked = <int, DateTime>{};
  final _newChats = ValueNotifier<Map<int, List<int>>>(const {});

  bool get isPremium => _premium;

  ValueListenable<Map<int, List<int>>> get newChats => _newChats;

  // ---- Folders --------------------------------------------------------------

  Future<td.ChatFolder> folder(int id) => _client.invoke<td.ChatFolder>(td.GetChatFolder(chatFolderId: id));

  Future<td.ChatFolderInfo> create(FolderDraft draft) async {
    final info = await _client.invoke<td.ChatFolderInfo>(
      td.CreateChatFolder(folder: draft.toFolder(sendColor: _premium)),
    );
    if (!_premium) _setLocalColor(info.id, draft.colorId);
    return info;
  }

  Future<td.ChatFolderInfo> edit(int id, FolderDraft draft) async {
    final info = await _client.invoke<td.ChatFolderInfo>(
      td.EditChatFolder(
        chatFolderId: id,
        folder: draft.toFolder(sendColor: _premium),
      ),
    );
    if (!_premium) _setLocalColor(id, draft.colorId);
    return info;
  }

  Future<void> delete(int id, {List<int> leaveChatIds = const []}) async {
    await _client.invoke<td.Ok>(td.DeleteChatFolder(chatFolderId: id, leaveChatIds: leaveChatIds));
    _setLocalColor(id, -1);
  }

  /// Chats of a joined shared folder that Telegram suggests leaving with it.
  Future<List<int>> chatsToLeave(int id) async =>
      (await _client.invoke<td.Chats>(td.GetChatFolderChatsToLeave(chatFolderId: id))).chatIds;

  Future<void> reorder(List<int> folderIds, int mainPosition) => _client.invoke<td.Ok>(
    td.ReorderChatFolders(chatFolderIds: folderIds, mainChatListPosition: mainPosition),
  );

  Future<List<td.RecommendedChatFolder>> recommended() async =>
      (await _client.invoke<td.RecommendedChatFolders>(const td.GetRecommendedChatFolders())).chatFolders;

  Future<void> addRecommended(td.ChatFolder folder) =>
      _client.invoke<td.ChatFolderInfo>(td.CreateChatFolder(folder: folder));

  Future<String> defaultIconName(FolderDraft draft) async => (await _client.invoke<td.ChatFolderIcon>(
    td.GetChatFolderDefaultIconName(folder: draft.toFolder(sendColor: false)),
  )).name;

  Future<void> setTagsEnabled(bool on) => _client.invoke<td.Ok>(td.ToggleChatFolderTags(areTagsEnabled: on));

  // ---- Chats in folders -----------------------------------------------------

  /// Folder ids the chat could be added to (TDLib knows the limits).
  Future<List<int>> foldersToAddChat(int chatId) async {
    final lists = await _client.invoke<td.ChatLists>(td.GetChatListsToAddChat(chatId: chatId));
    return [
      for (final l in lists.chatLists)
        if (l case td.ChatListFolder(:final chatFolderId)) chatFolderId,
    ];
  }

  Future<void> setChatInFolder(int chatId, int folderId, {required bool inFolder}) async {
    if (inFolder) {
      await _client.invoke<td.Ok>(
        td.AddChatToList(
          chatId: chatId,
          chatList: td.ChatListFolder(chatFolderId: folderId),
        ),
      );
      return;
    }
    final f = await folder(folderId);
    final draft = FolderDraft.fromFolder(f).withChat(chatId, included: false);
    await _client.invoke<td.ChatFolderInfo>(
      td.EditChatFolder(
        chatFolderId: folderId,
        folder: draft.toFolder(sendColor: _premium),
      ),
    );
  }

  Future<void> readAll(td.ChatList list) => _client.invoke<td.Ok>(td.ReadChatList(chatList: list));

  /// Mutes or unmutes every loaded chat of [list].
  Future<void> setAllMuted(td.ChatList list, {required bool muted}) async {
    for (final chat in _cache.chatsIn(list)) {
      await _client.invoke<td.Ok>(
        td.SetChatNotificationSettings(
          chatId: chat.id,
          notificationSettings: chat.notificationSettings.copyWith(
            useDefaultMuteFor: false,
            muteFor: muted ? 0x7fffffff : 0,
          ),
        ),
      );
    }
  }

  Future<List<int>> searchChats(String query) async {
    if (query.trim().isEmpty) return const [];
    return (await _client.invoke<td.Chats>(td.SearchChats(query: query, limit: 50))).chatIds;
  }

  // ---- Invite links ---------------------------------------------------------

  Future<List<td.ChatFolderInviteLink>> inviteLinks(int id) async =>
      (await _client.invoke<td.ChatFolderInviteLinks>(td.GetChatFolderInviteLinks(chatFolderId: id)))
          .inviteLinks;

  Future<List<int>> shareableChats(int id) async =>
      (await _client.invoke<td.Chats>(td.GetChatsForChatFolderInviteLink(chatFolderId: id))).chatIds;

  Future<td.ChatFolderInviteLink> createLink(int id, {required String name, required List<int> chatIds}) =>
      _client.invoke<td.ChatFolderInviteLink>(
        td.CreateChatFolderInviteLink(chatFolderId: id, name: name, chatIds: chatIds),
      );

  Future<td.ChatFolderInviteLink> editLink(
    int id,
    String link, {
    required String name,
    required List<int> chatIds,
  }) => _client.invoke<td.ChatFolderInviteLink>(
    td.EditChatFolderInviteLink(chatFolderId: id, inviteLink: link, name: name, chatIds: chatIds),
  );

  Future<void> deleteLink(int id, String link) =>
      _client.invoke<td.Ok>(td.DeleteChatFolderInviteLink(chatFolderId: id, inviteLink: link));

  Future<td.ChatFolderInviteLinkInfo> checkLink(String url) =>
      _client.invoke<td.ChatFolderInviteLinkInfo>(td.CheckChatFolderInviteLink(inviteLink: url));

  Future<void> join(String url, List<int> chatIds) =>
      _client.invoke<td.Ok>(td.AddChatFolderByInviteLink(inviteLink: url, chatIds: chatIds));

  // ---- New chats in joined shared folders -----------------------------------

  /// Asks TDLib for new chats in every shared folder we joined (shareable,
  /// no links of our own), at most once per [newChatsPeriod] per folder.
  Future<void> refreshNewChats() async {
    final next = {..._newChats.value};
    for (final f in _cache.chatFolders) {
      if (!f.isShareable || f.hasMyInviteLinks) continue;
      final last = _lastChecked[f.id];
      if (last != null && _now().difference(last) < newChatsPeriod) continue;
      _lastChecked[f.id] = _now();
      try {
        final chats = await _client.invoke<td.Chats>(td.GetChatFolderNewChats(chatFolderId: f.id));
        if (chats.chatIds.isEmpty) {
          next.remove(f.id);
        } else {
          next[f.id] = chats.chatIds;
        }
      } on Exception {
        // Offline or rate-limited; the next refresh retries.
      }
    }
    _newChats.value = next;
  }

  Future<void> processNewChats(int id, List<int> added) async {
    await _client.invoke<td.Ok>(td.ProcessChatFolderNewChats(chatFolderId: id, addedChatIds: added));
    _newChats.value = {..._newChats.value}..remove(id);
  }

  // ---- Colours ---------------------------------------------------------------

  /// Telegram's colour when set, else this device's choice, else -1.
  int colorIdOf(td.ChatFolderInfo info) => info.colorId >= 0 ? info.colorId : localColor(info.id) ?? -1;

  int? localColor(int folderId) =>
      (jsonDecode(_prefs.folderColorsJson) as Map<String, dynamic>)['$folderId'] as int?;

  void _setLocalColor(int folderId, int colorId) {
    final map = (jsonDecode(_prefs.folderColorsJson) as Map<String, dynamic>)..remove('$folderId');
    if (colorId >= 0) map['$folderId'] = colorId;
    _prefs.folderColorsJson = jsonEncode(map);
  }

  /// Checks for new shared-folder chats whenever the folder list arrives or
  /// changes (startup included); [refreshNewChats] throttles per folder.
  void watchFolders() => _foldersSub ??= _cache.events
      .where((e) => e is FoldersChanged)
      .listen((_) => refreshNewChats().ignore());

  Future<void> dispose() async {
    await _foldersSub?.cancel();
    await _sub.cancel();
    _newChats.dispose();
  }
}
