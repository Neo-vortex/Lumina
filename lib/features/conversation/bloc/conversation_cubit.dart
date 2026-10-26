import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/tdlib/td_errors.dart';
import '../../../core/telegram/telegram_cache.dart';
import '../../../core/telegram/entity_edit.dart';
import '../data/messages_repository.dart';

part 'conversation_state.dart';

/// One open conversation: a window of messages kept live by TDLib updates,
/// plus composer state (reply / edit), selection and the pinned banner.
class ConversationCubit extends Cubit<ConversationState> {
  ConversationCubit({
    required int chatId,
    required this._repository,
    required this._cache,
    required Stream<td.Update> updates,
    this.showSponsored = false,
  }) : super(ConversationState(chatId: chatId, chat: _cache.chats[chatId])) {
    _updates = updates.listen(_onUpdate);
    _cacheEvents = _cache.events.listen(_onCacheEvent);
  }

  final MessagesRepository _repository;
  final TelegramCache _cache;

  /// Load channel sponsored messages (decided by the screen from account
  /// type and the user's preference).
  final bool showSponsored;
  final _viewedSponsored = <int>{};
  late final StreamSubscription<td.Update> _updates;
  late final StreamSubscription<CacheEvent> _cacheEvents;
  final _pendingViews = <int>{};
  Timer? _viewDebounce;
  Timer? _highlightTimer;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);
  var _anchorSerial = 0;

  int get chatId => state.chatId;

  static const _page = 50;

  /// [focusMessageId] opens the chat at that message (search results).
  Future<void> start({int? focusMessageId}) async {
    try {
      await _repository.openChat(chatId);
    } on TdException catch (e) {
      emit(state.copyWith(error: () => e.message));
    }
    final chat = state.chat ?? _cache.chats[chatId];
    final lastRead = chat?.lastReadInboxMessageId ?? 0;
    if (focusMessageId != null) {
      await _loadAround(focusMessageId, highlight: true);
    } else if (chat != null && chat.unreadCount > 0 && lastRead > 0) {
      await _loadAround(lastRead, markUnreadAfter: lastRead);
    } else {
      await _loadLatest();
    }
    unawaited(_refreshPinned());
    if (showSponsored) unawaited(_loadSponsored());
  }

  Future<void> _loadSponsored() async {
    try {
      final ads = await _repository.sponsored(chatId);
      if (!isClosed) emit(state.copyWith(sponsored: ads));
    } on TdException {
      // Not a channel with ads.
    }
  }

  void sponsoredVisible(td.SponsoredMessage ad) {
    if (_viewedSponsored.add(ad.messageId)) _repository.viewSponsored(chatId, ad.messageId).ignore();
  }

  Future<void> sponsoredClicked(td.SponsoredMessage ad) => _repository.clickSponsored(chatId, ad.messageId);

  // ---- Loading ---------------------------------------------------------------

  Future<void> _loadLatest({bool scroll = false}) async {
    emit(state.copyWith(initialLoading: state.messages.isEmpty));
    try {
      var messages = await _repository.history(chatId, limit: _page);
      // TDLib's first answer may come only from the local cache; ask again.
      if (messages.length < 10) {
        final more = await _repository.history(chatId, limit: _page);
        if (more.length > messages.length) messages = more;
      }
      emit(
        state.copyWith(
          messages: messages,
          initialLoading: false,
          hasNewer: false,
          hasOlder: messages.isNotEmpty,
          anchor: scroll && messages.isNotEmpty ? () => _anchorFor(messages.first.id) : null,
        ),
      );
    } on TdException catch (e) {
      emit(state.copyWith(initialLoading: false, error: () => e.message));
    }
  }

  Future<void> _loadAround(int messageId, {int? markUnreadAfter, bool highlight = false}) async {
    emit(state.copyWith(initialLoading: state.messages.isEmpty));
    try {
      final messages = await _repository.history(
        chatId,
        fromMessageId: messageId,
        offset: -(_page ~/ 2),
        limit: _page,
      );
      final latestId = (_cache.chats[chatId] ?? state.chat)?.lastMessage?.id ?? 0;
      final firstUnread = markUnreadAfter == null
          ? null
          : messages
                .where((m) => m.id > markUnreadAfter && !m.isOutgoing)
                .map((m) => m.id)
                .fold<int?>(null, (min, id) => min == null || id < min ? id : min);
      final target = firstUnread ?? messageId;
      emit(
        state.copyWith(
          messages: messages,
          initialLoading: false,
          hasOlder: true,
          hasNewer: messages.isNotEmpty && messages.first.id < latestId,
          firstUnreadId: markUnreadAfter == null ? null : () => firstUnread,
          anchor: () => _anchorFor(target),
          highlightId: highlight ? () => messageId : null,
        ),
      );
      if (highlight) _clearHighlightLater();
    } on TdException catch (e) {
      emit(state.copyWith(initialLoading: false, error: () => e.message));
    }
  }

  ({int messageId, int serial}) _anchorFor(int id) => (messageId: id, serial: ++_anchorSerial);

  Future<void> loadOlder() async {
    if (state.loadingOlder || !state.hasOlder || state.messages.isEmpty) return;
    emit(state.copyWith(loadingOlder: true));
    try {
      final oldest = state.messages.last.id;
      final older = await _repository.history(chatId, fromMessageId: oldest, limit: _page);
      final fresh = older.where((m) => m.id < oldest).toList();
      emit(
        state.copyWith(
          messages: [...state.messages, ...fresh],
          loadingOlder: false,
          hasOlder: fresh.isNotEmpty,
        ),
      );
    } on TdException {
      emit(state.copyWith(loadingOlder: false));
    }
  }

  Future<void> loadNewer() async {
    if (state.loadingNewer || !state.hasNewer || state.messages.isEmpty) return;
    emit(state.copyWith(loadingNewer: true));
    try {
      final newest = state.messages.first.id;
      final batch = await _repository.history(
        chatId,
        fromMessageId: newest,
        offset: -(_page - 1),
        limit: _page,
      );
      final fresh = batch.where((m) => m.id > newest).toList();
      final latestId = _cache.chats[chatId]?.lastMessage?.id ?? 0;
      emit(
        state.copyWith(
          messages: [...fresh, ...state.messages],
          loadingNewer: false,
          hasNewer: fresh.isNotEmpty && fresh.first.id < latestId,
        ),
      );
    } on TdException {
      emit(state.copyWith(loadingNewer: false));
    }
  }

  /// Scroll-to-bottom button: newest message, reloading if the window is old.
  Future<void> jumpToLatest() async {
    if (state.hasNewer) {
      await _loadLatest(scroll: true);
    } else if (state.messages.isNotEmpty) {
      emit(state.copyWith(anchor: () => _anchorFor(state.messages.first.id)));
    }
  }

  /// Reply quote, pinned banner or search result tap.
  Future<void> jumpTo(int messageId) async {
    if (state.messages.any((m) => m.id == messageId)) {
      emit(state.copyWith(anchor: () => _anchorFor(messageId), highlightId: () => messageId));
      _clearHighlightLater();
    } else {
      await _loadAround(messageId, highlight: true);
    }
  }

  void _clearHighlightLater() {
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!isClosed) emit(state.copyWith(highlightId: () => null));
    });
  }

  Future<void> _refreshPinned() async {
    final pinned = await _repository.pinnedMessage(chatId);
    if (!isClosed) emit(state.copyWith(pinned: () => pinned));
  }

  // ---- Reading ---------------------------------------------------------------

  /// Called by the list with the ids currently on screen.
  void visible(Iterable<int> messageIds) {
    final lastRead = _cache.chats[chatId]?.lastReadInboxMessageId ?? 0;
    final fresh = messageIds.where((id) => id > lastRead && !_pendingViews.contains(id));
    if (fresh.isEmpty) return;
    _pendingViews.addAll(fresh);
    _viewDebounce ??= Timer(const Duration(milliseconds: 400), () {
      _viewDebounce = null;
      final ids = _pendingViews.toList();
      _pendingViews.clear();
      _repository.view(chatId, ids).ignore();
    });
  }

  /// Explicit read, honoured even when read receipts are hidden.
  Future<void> markAllRead() async {
    final latest = _cache.chats[chatId]?.lastMessage?.id;
    if (latest != null) await _repository.view(chatId, [latest], force: true);
  }

  // ---- Composer --------------------------------------------------------------

  /// Reply to [message], optionally quoting part of its text.
  void startReply(td.Message message, {td.InputTextQuote? quote}) =>
      emit(state.copyWith(replyTo: () => message, replyQuote: () => quote, editing: () => null));

  /// Brings back the reply (and quote) a saved draft points at.
  Future<void> restoreDraftReply(td.InputMessageReplyTo? replyTo) async {
    if (replyTo is! td.InputMessageReplyToMessage || state.replyTo != null) return;
    final m = await messageById(replyTo.messageId);
    if (m != null && !isClosed && state.replyTo == null && state.editing == null) {
      startReply(m, quote: replyTo.quote);
    }
  }

  void startEdit(td.Message message) => emit(state.copyWith(editing: () => message, replyTo: () => null));

  void cancelComposerMode() => emit(state.copyWith(replyTo: () => null, editing: () => null));

  /// Sends (or saves an edit). Returns an error message, or null on success.
  Future<String?> send(
    String text, {
    List<td.TextEntity> entities = const [],
    SendOptions options = const SendOptions(),
    td.LinkPreviewOptions? linkPreview,
  }) async {
    final f = EntityEdit.trim(text, entities);
    if (f.text.isEmpty) return null;
    final editing = state.editing;
    final replyTo = state.replyTo;
    try {
      if (editing != null) {
        await _repository.editText(
          chatId,
          editing.id,
          f.text,
          entities: f.entities,
          linkPreviewOptions: linkPreview,
        );
      } else {
        if (state.hasNewer) await _loadLatest(scroll: true);
        await _repository.sendText(
          chatId,
          f.text,
          entities: f.entities,
          replyToMessageId: replyTo?.id,
          quote: state.replyQuote,
          options: options,
          linkPreviewOptions: linkPreview,
        );
      }
      emit(state.copyWith(replyTo: () => null, editing: () => null));
      return null;
    } on TdException catch (e) {
      return e.message;
    }
  }

  /// [onSent] gets the pending message (temporary id until TDLib confirms).
  Future<String?> sendContent(
    td.InputMessageContent content, {
    SendOptions options = const SendOptions(),
    void Function(td.Message pending)? onSent,
  }) async {
    try {
      if (state.hasNewer) await _loadLatest(scroll: true);
      final pending = await _repository.sendContent(
        chatId,
        content,
        replyToMessageId: state.replyTo?.id,
        quote: state.replyQuote,
        options: options,
      );
      onSent?.call(pending);
      emit(state.copyWith(replyTo: () => null));
      return null;
    } on TdException catch (e) {
      return e.message;
    }
  }

  Future<String?> sendAlbum(
    List<td.InputMessageContent> contents, {
    SendOptions options = const SendOptions(),
  }) async {
    try {
      if (state.hasNewer) await _loadLatest(scroll: true);
      await _repository.sendAlbum(
        chatId,
        contents,
        replyToMessageId: state.replyTo?.id,
        quote: state.replyQuote,
        options: options,
      );
      emit(state.copyWith(replyTo: () => null));
      return null;
    } on TdException catch (e) {
      return e.message;
    }
  }

  /// Typing indicator, at most every 4 s while the user types.
  void composerChanged(String text) {
    if (text.isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastTypingSent) < const Duration(seconds: 4)) return;
    _lastTypingSent = now;
    _repository.sendAction(chatId, const td.ChatActionTyping()).ignore();
  }

  void chatAction(td.ChatAction? action) => _repository.sendAction(chatId, action).ignore();

  Future<void> saveDraft(String text, {List<td.TextEntity> entities = const []}) => _repository
      .saveDraft(
        chatId,
        text,
        entities: entities,
        replyToMessageId: state.replyTo?.id,
        quote: state.replyQuote,
      )
      .catchError((Object e) => debugPrint('Saving the draft failed: $e'));

  Future<td.LinkPreview?> linkPreview(td.FormattedText text) => _repository.linkPreview(text);

  // ---- Message actions -------------------------------------------------------

  Future<td.MessageProperties?> properties(td.Message m) async {
    try {
      return await _repository.properties(chatId, m.id);
    } on TdException {
      return null;
    }
  }

  Future<void> delete(List<int> ids, {required bool forEveryone}) async {
    await _repository.delete(chatId, ids, forEveryone: forEveryone);
    clearSelection();
  }

  Future<void> pin(td.Message m, {bool notify = false}) async {
    await _repository.pin(chatId, m.id, notify: notify);
    await _refreshPinned();
  }

  Future<void> unpin(td.Message m) async {
    await _repository.unpin(chatId, m.id);
    await _refreshPinned();
  }

  Future<void> toggleReaction(td.Message m, String emoji) async {
    final reaction = td.ReactionTypeEmoji(emoji: emoji);
    final chosen =
        m.interactionInfo?.reactions?.reactions.any(
          (r) =>
              r.isChosen && r.type is td.ReactionTypeEmoji && (r.type as td.ReactionTypeEmoji).emoji == emoji,
        ) ??
        false;
    await _repository.react(chatId, m.id, reaction, add: !chosen);
  }

  Future<List<String>> reactionChoices(td.Message m) async {
    try {
      final types = await _repository.availableReactions(chatId, m.id);
      return [for (final t in types) (t as td.ReactionTypeEmoji).emoji];
    } on TdException {
      return const [];
    }
  }

  /// A message from the window, or fetched from TDLib (reply quotes).
  Future<td.Message?> messageById(int id) async {
    for (final m in state.messages) {
      if (m.id == id) return m;
    }
    try {
      return await _repository.message(chatId, id);
    } on TdException {
      return null;
    }
  }

  Future<void> openViewOnce(td.Message m) => _repository.openContent(chatId, m.id);

  // ---- Selection -------------------------------------------------------------

  void toggleSelected(td.Message m) {
    final next = {...state.selected};
    if (!next.remove(m.id)) next.add(m.id);
    emit(state.copyWith(selected: next));
  }

  void clearSelection() => emit(state.copyWith(selected: const {}));

  // ---- Updates ---------------------------------------------------------------

  void _onUpdate(td.Update u) {
    switch (u) {
      case td.UpdateNewMessage(:final message) when message.chatId == chatId:
        // Scheduled messages live in their own list until they're sent.
        if (message.schedulingState != null) return;
        if (state.hasNewer || state.messages.any((m) => m.id == message.id)) return;
        emit(state.copyWith(messages: [message, ...state.messages]));
      case td.UpdateMessageSendSucceeded(:final message, :final oldMessageId) when message.chatId == chatId:
        _replace(oldMessageId, (_) => message);
      case td.UpdateMessageSendFailed(:final message, :final oldMessageId) when message.chatId == chatId:
        _replace(oldMessageId, (_) => message);
      case td.UpdateMessageContent(chatId: final c, :final messageId, :final newContent) when c == chatId:
        _replace(messageId, (m) => m.copyWith(content: newContent));
      case td.UpdateMessageEdited(chatId: final c, :final messageId, :final editDate) when c == chatId:
        _replace(messageId, (m) => m.copyWith(editDate: editDate));
      case td.UpdateMessageInteractionInfo(chatId: final c, :final messageId, :final interactionInfo)
          when c == chatId && interactionInfo != null:
        _replace(messageId, (m) => m.copyWith(interactionInfo: interactionInfo));
      case td.UpdateMessageIsPinned(chatId: final c, :final messageId, :final isPinned) when c == chatId:
        _replace(messageId, (m) => m.copyWith(isPinned: isPinned));
        unawaited(_refreshPinned());
      case td.UpdateDeleteMessages(chatId: final c, :final messageIds, :final fromCache)
          when c == chatId && !fromCache:
        final gone = messageIds.toSet();
        emit(
          state.copyWith(
            messages: state.messages.where((m) => !gone.contains(m.id)).toList(),
            selected: state.selected.difference(gone),
            replyTo: gone.contains(state.replyTo?.id) ? () => null : null,
            editing: gone.contains(state.editing?.id) ? () => null : null,
          ),
        );
      default:
        break;
    }
  }

  void _replace(int messageId, td.Message Function(td.Message) change) {
    final index = state.messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return;
    final next = [...state.messages];
    next[index] = change(next[index]);
    next.sort((a, b) => b.id.compareTo(a.id));
    emit(state.copyWith(messages: next));
  }

  void _onCacheEvent(CacheEvent e) {
    final relevant = switch (e) {
      ChatChanged(:final chatId) => chatId == this.chatId,
      TypingChanged(:final chatId) => chatId == this.chatId,
      UserChanged() => true,
      // Membership and rights (joining, leaving, being promoted) decide
      // whether the composer or the bottom bar shows.
      GroupChanged(:final basicGroupId, :final supergroupId) => switch (_cache.chats[chatId]?.type) {
        td.ChatTypeBasicGroup(basicGroupId: final id) => id == basicGroupId,
        td.ChatTypeSupergroup(supergroupId: final id) => id == supergroupId,
        _ => false,
      },
      SecretChatChanged(:final secretChatId) => switch (_cache.chats[chatId]?.type) {
        td.ChatTypeSecret(secretChatId: final id) => id == secretChatId,
        _ => false,
      },
      _ => false,
    };
    if (relevant && !isClosed) {
      emit(state.copyWith(chat: _cache.chats[chatId], revision: state.revision + 1));
    }
  }

  @override
  Future<void> close() async {
    _viewDebounce?.cancel();
    _highlightTimer?.cancel();
    await _updates.cancel();
    await _cacheEvents.cancel();
    _repository.closeChat(chatId).ignore();
    return super.close();
  }
}
