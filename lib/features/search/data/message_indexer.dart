import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:handy_tdlib_next/api.dart' as td;
import 'package:path_provider/path_provider.dart';

import '../../../core/search/message_search.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../core/storage/secure_store.dart';
import '../../../core/tdlib/td_client.dart';
import '../../../core/tdlib/td_errors.dart';
import '../../../core/telegram/telegram_cache.dart';
import 'search_db.dart';
import 'search_worker.dart';

/// Local, encrypted full-text index of message text and captions.
///
/// New, edited and deleted messages are mirrored live from TDLib updates;
/// older history is walked in the background at a gentle pace. The index is
/// deleted whenever the session closes. This deliberately duplicates
/// message text (spec §3.4 allows it for a specific performance reason:
/// fast, exact search in any script, which TDLib's search can't provide).
class MessageIndexer extends ChangeNotifier implements MessageSearch {
  MessageIndexer({required this._client, required this._cache, required this._secure, required this._prefs}) {
    _sub = _client.updates.listen(_onUpdate);
    _prefs.changes.addListener(_onPrefs);
  }

  final TdClient _client;
  final TelegramCache _cache;
  final SecureStore _secure;
  final AppPreferences _prefs;
  StreamSubscription<td.Update>? _sub;
  SearchWorker? _worker;
  Future<SearchWorker?>? _opening;
  final _queue = <IndexRecord>[];
  Timer? _flush;
  var _isBot = false;
  var _backfilling = false;

  /// Live progress for settings ("indexed N messages in M chats").
  ({int messages, int chats}) stats = (messages: 0, chats: 0);
  bool get backfilling => _backfilling;

  @override
  bool get enabled => _prefs.searchIndexEnabled && _worker != null;

  static String? textOf(td.MessageContent c) {
    final t = switch (c) {
      td.MessageText(:final text) => text.text,
      td.MessagePhoto(:final caption) ||
      td.MessageVideo(:final caption) ||
      td.MessageDocument(:final caption) ||
      td.MessageAudio(:final caption) ||
      td.MessageAnimation(:final caption) ||
      td.MessageVoiceNote(:final caption) => caption.text,
      _ => null,
    };
    return t == null || t.trim().isEmpty ? null : t;
  }

  static int _sender(td.MessageSender s) => switch (s) {
    td.MessageSenderUser(:final userId) => userId,
    td.MessageSenderChat(:final chatId) => chatId,
  };

  static IndexRecord? recordOf(td.Message m) {
    final text = textOf(m.content);
    if (text == null) return null;
    return IndexRecord(
      chatId: m.chatId,
      messageId: m.id,
      date: m.date,
      senderId: _sender(m.senderId),
      text: text,
    );
  }

  /// Starts indexing once signed in. [isBot] disables history backfill
  /// (bots cannot read chat history).
  Future<void> activate({required bool isBot}) async {
    _isBot = isBot;
    if (!_prefs.searchIndexEnabled) return;
    await _open();
    unawaited(_refreshStats());
    unawaited(_backfillLoop());
  }

  Future<SearchWorker?> _open() => _opening ??= () async {
    final dir = await getApplicationSupportDirectory();
    final folder = Directory('${dir.path}/search')..createSync(recursive: true);
    var key = await _secure.readSecret('search.key');
    if (key == null) {
      final r = Random.secure();
      key = List.generate(32, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await _secure.writeSecret('search.key', key);
    }
    return _worker = await SearchWorker.spawn('${folder.path}/index.db', key);
  }();

  void _onPrefs() {
    if (!_prefs.searchIndexEnabled && _worker != null) {
      unawaited(wipe());
    }
  }

  void _onUpdate(td.Update u) {
    switch (u) {
      case td.UpdateAuthorizationState(authorizationState: td.AuthorizationStateClosed()):
        unawaited(wipe());
        return;
      default:
        break;
    }
    if (!_prefs.searchIndexEnabled) return;
    final w = _worker;
    if (w == null) return;
    switch (u) {
      case td.UpdateNewMessage(:final message) when message.sendingState == null:
        _enqueue(recordOf(message));
      case td.UpdateMessageSendSucceeded(:final message, :final oldMessageId):
        w.delete(message.chatId, [oldMessageId]).ignore();
        _enqueue(recordOf(message));
      case td.UpdateMessageContent(:final chatId, :final messageId, :final newContent):
        final text = textOf(newContent);
        if (text == null) {
          w.delete(chatId, [messageId]).ignore();
        } else {
          _enqueue(
            IndexRecord(
              chatId: chatId,
              messageId: messageId,
              date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              senderId: 0,
              text: text,
            ),
          );
        }
      case td.UpdateDeleteMessages(:final chatId, :final messageIds, :final fromCache) when !fromCache:
        w.delete(chatId, messageIds).ignore();
      default:
        break;
    }
  }

  void _enqueue(IndexRecord? r) {
    if (r == null) return;
    _queue.add(r);
    _flush ??= Timer(const Duration(milliseconds: 400), () {
      _flush = null;
      final batch = List.of(_queue);
      _queue.clear();
      _worker?.upsert(batch).ignore();
    });
  }

  /// Walks chat histories newest → oldest, a page at a time, pausing between
  /// pages so TDLib and the network stay responsive.
  Future<void> _backfillLoop() async {
    if (_backfilling || _isBot) return;
    _backfilling = true;
    notifyListeners();
    try {
      var pass = 0;
      while (_prefs.searchIndexEnabled && _prefs.searchBackfill && _worker != null && pass < 50) {
        pass++;
        var progressed = false;
        for (final chat in _cache.chatsIn(const td.ChatListMain()).take(300)) {
          if (!_prefs.searchBackfill || _worker == null) return;
          if (await _backfillChat(chat.id, maxPages: 5)) progressed = true;
        }
        await _refreshStats();
        if (!progressed) break;
      }
    } finally {
      _backfilling = false;
      notifyListeners();
    }
  }

  /// Returns true if anything was indexed.
  Future<bool> _backfillChat(int chatId, {required int maxPages}) async {
    final w = _worker!;
    final p = await w.progress(chatId);
    if (p?.done ?? false) return false;
    var from = p?.oldestId ?? 0;
    var any = false;
    for (var page = 0; page < maxPages; page++) {
      td.Messages result;
      try {
        result = await _client.invoke<td.Messages>(
          td.GetChatHistory(chatId: chatId, fromMessageId: from, offset: 0, limit: 100, onlyLocal: false),
        );
      } on TdException {
        await w.setProgress(chatId, from, done: true);
        return any;
      }
      final older = result.messages.where((m) => from == 0 || m.id < from).toList();
      if (older.isEmpty) {
        await w.setProgress(chatId, from, done: true);
        return any;
      }
      await w.upsert([for (final m in older) ?recordOf(m)]);
      from = older.map((m) => m.id).reduce(min);
      await w.setProgress(chatId, from, done: false);
      any = true;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return any;
  }

  Future<void> _refreshStats() async {
    final w = _worker;
    if (w == null) return;
    stats = await w.stats();
    notifyListeners();
  }

  @override
  Future<List<MessageHit>> search(String query, {int? chatId, int limit = 100}) async {
    final w = await (_worker != null
        ? Future.value(_worker)
        : (_prefs.searchIndexEnabled ? _open() : Future.value(null)));
    if (w == null) return const [];
    return w.search(query, chatId: chatId, limit: limit);
  }

  /// Deletes the index and its key (logout, or the user turned it off).
  Future<void> wipe() async {
    final w = _worker;
    _worker = null;
    _opening = null;
    _queue.clear();
    if (w != null) {
      await w.clear().catchError((_) {});
      w.dispose();
    }
    final dir = await getApplicationSupportDirectory();
    final folder = Directory('${dir.path}/search');
    if (await folder.exists()) await folder.delete(recursive: true).catchError((_) => folder);
    await _secure.writeSecret('search.key', null);
    stats = (messages: 0, chats: 0);
    notifyListeners();
  }

  /// Settings → "Rebuild index".
  Future<void> rebuild() async {
    await wipe();
    await activate(isBot: _isBot);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _flush?.cancel();
    _prefs.changes.removeListener(_onPrefs);
    _worker?.dispose();
    super.dispose();
  }
}
