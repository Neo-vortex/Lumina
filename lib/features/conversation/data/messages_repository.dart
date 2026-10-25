import 'package:handy_tdlib_next/api.dart' as td;

import '../../../core/tdlib/td_errors.dart';

import '../../../core/storage/app_preferences.dart';
import '../../../core/tdlib/td_client.dart';

/// How a message should be sent (user requests: silent, scheduled,
/// send-when-online).
class SendOptions {
  const SendOptions({this.silent = false, this.scheduleAt, this.whenOnline = false});

  final bool silent;
  final DateTime? scheduleAt;
  final bool whenOnline;

  td.MessageSendOptions toTd() => td.MessageSendOptions(
    disableNotification: silent,
    fromBackground: false,
    protectContent: false,
    updateOrderOfInstalledStickerSets: false,
    schedulingState: whenOnline
        ? const td.MessageSchedulingStateSendWhenOnline()
        : scheduleAt != null
        ? td.MessageSchedulingStateSendAtDate(sendDate: scheduleAt!.millisecondsSinceEpoch ~/ 1000)
        : null,
    effectId: 0,
    sendingId: 0,
    onlyPreview: false,
  );
}

/// Message operations for one or more chats. TDLib owns the messages; this
/// is a thin, testable facade over the requests.
class MessagesRepository {
  MessagesRepository({required this._client, required this._prefs});

  final TdClient _client;
  final AppPreferences _prefs;

  Future<void> openChat(int chatId) => _client.invoke<td.Ok>(td.OpenChat(chatId: chatId));

  Future<void> closeChat(int chatId) => _client.invoke<td.Ok>(td.CloseChat(chatId: chatId));

  /// Messages older than [fromMessageId] (0 = newest), newest first.
  /// [offset] < 0 also returns up to -offset newer messages.
  Future<List<td.Message>> history(
    int chatId, {
    int fromMessageId = 0,
    int offset = 0,
    int limit = 50,
  }) async {
    final result = await _client.invoke<td.Messages>(
      td.GetChatHistory(
        chatId: chatId,
        fromMessageId: fromMessageId,
        offset: offset,
        limit: limit,
        onlyLocal: false,
      ),
    );
    return result.messages;
  }

  Future<td.Message> message(int chatId, int messageId) =>
      _client.invoke<td.Message>(td.GetMessage(chatId: chatId, messageId: messageId));

  /// Marks messages as read, unless the user asked not to send read receipts
  /// ([force] overrides that: explicit "Mark as read").
  Future<void> view(int chatId, List<int> messageIds, {bool force = false}) async {
    if (messageIds.isEmpty) return;
    if (_prefs.hideReadReceipts && !force) return;
    await _client.invoke<td.Ok>(td.ViewMessages(chatId: chatId, messageIds: messageIds, forceRead: true));
  }

  /// Parses `**bold**`, `__italic__`, `~~strike~~`, `||spoiler||`, `` `code` ``
  /// and `[text](url)` into entities via TDLib's own parser.
  Future<td.FormattedText> parseMarkdown(String text) async {
    final result = await _client.execute(
      td.ParseMarkdown(
        text: td.FormattedText(text: text, entities: const []),
      ),
    );
    return result is td.FormattedText ? result : td.FormattedText(text: text, entities: const []);
  }

  /// Hand-applied [entities] win; otherwise Markdown in [text] is parsed.
  Future<td.FormattedText> _format(String text, List<td.TextEntity> entities) async =>
      entities.isEmpty ? parseMarkdown(text) : td.FormattedText(text: text, entities: entities);

  /// The preview Telegram would attach to [text], or null.
  Future<td.LinkPreview?> linkPreview(td.FormattedText text) async {
    try {
      return await _client.invoke<td.LinkPreview>(td.GetLinkPreview(text: text));
    } on TdException {
      return null;
    }
  }

  Future<td.Message> sendText(
    int chatId,
    String text, {
    List<td.TextEntity> entities = const [],
    int? replyToMessageId,
    SendOptions options = const SendOptions(),
    bool disableLinkPreview = false,
    td.LinkPreviewOptions? linkPreviewOptions,
  }) async {
    final formatted = await _format(text, entities);
    return _client.invoke<td.Message>(
      td.SendMessage(
        chatId: chatId,
        messageThreadId: 0,
        replyTo: replyToMessageId == null ? null : td.InputMessageReplyToMessage(messageId: replyToMessageId),
        options: options.toTd(),
        inputMessageContent: td.InputMessageText(
          text: formatted,
          linkPreviewOptions:
              linkPreviewOptions ??
              (disableLinkPreview
                  ? const td.LinkPreviewOptions(
                      isDisabled: true,
                      url: '',
                      forceSmallMedia: false,
                      forceLargeMedia: false,
                      showAboveText: false,
                    )
                  : null),
          clearDraft: true,
        ),
      ),
    );
  }

  /// Sends arbitrary content (media, voice, ...) built by other features.
  Future<td.Message> sendContent(
    int chatId,
    td.InputMessageContent content, {
    int? replyToMessageId,
    SendOptions options = const SendOptions(),
  }) => _client.invoke<td.Message>(
    td.SendMessage(
      chatId: chatId,
      messageThreadId: 0,
      replyTo: replyToMessageId == null ? null : td.InputMessageReplyToMessage(messageId: replyToMessageId),
      options: options.toTd(),
      inputMessageContent: content,
    ),
  );

  Future<void> sendAlbum(
    int chatId,
    List<td.InputMessageContent> contents, {
    int? replyToMessageId,
    SendOptions options = const SendOptions(),
  }) => _client.invoke<td.Messages>(
    td.SendMessageAlbum(
      chatId: chatId,
      messageThreadId: 0,
      replyTo: replyToMessageId == null ? null : td.InputMessageReplyToMessage(messageId: replyToMessageId),
      options: options.toTd(),
      inputMessageContents: contents,
    ),
  );

  Future<void> editText(
    int chatId,
    int messageId,
    String text, {
    List<td.TextEntity> entities = const [],
    td.LinkPreviewOptions? linkPreviewOptions,
  }) async {
    final formatted = await _format(text, entities);
    await _client.invoke<td.Message>(
      td.EditMessageText(
        chatId: chatId,
        messageId: messageId,
        inputMessageContent: td.InputMessageText(
          text: formatted,
          linkPreviewOptions: linkPreviewOptions,
          clearDraft: false,
        ),
      ),
    );
  }

  /// [forEveryone] = revoke for all participants when allowed.
  Future<void> delete(int chatId, List<int> messageIds, {required bool forEveryone}) =>
      _client.invoke<td.Ok>(td.DeleteMessages(chatId: chatId, messageIds: messageIds, revoke: forEveryone));

  /// Forwards; [hideSender] sends a copy without the "Forwarded from" header
  /// (user request), [removeCaption] also drops media captions.
  Future<void> forward({
    required int toChatId,
    required int fromChatId,
    required List<int> messageIds,
    bool hideSender = false,
    bool removeCaption = false,
    SendOptions options = const SendOptions(),
  }) => _client.invoke<td.Messages>(
    td.ForwardMessages(
      chatId: toChatId,
      messageThreadId: 0,
      fromChatId: fromChatId,
      messageIds: messageIds,
      options: options.toTd(),
      sendCopy: hideSender,
      removeCaption: hideSender && removeCaption,
    ),
  );

  Future<void> pin(int chatId, int messageId, {bool notify = false, bool onlyForSelf = false}) =>
      _client.invoke<td.Ok>(
        td.PinChatMessage(
          chatId: chatId,
          messageId: messageId,
          disableNotification: !notify,
          onlyForSelf: onlyForSelf,
        ),
      );

  Future<void> unpin(int chatId, int messageId) =>
      _client.invoke<td.Ok>(td.UnpinChatMessage(chatId: chatId, messageId: messageId));

  Future<td.Message?> pinnedMessage(int chatId) async {
    try {
      return await _client.invoke<td.Message>(td.GetChatPinnedMessage(chatId: chatId));
    } on Exception {
      return null;
    }
  }

  Future<List<td.Message>> searchInChat(
    int chatId,
    String query, {
    int fromMessageId = 0,
    td.SearchMessagesFilter? filter,
    int limit = 50,
  }) async {
    final found = await _client.invoke<td.FoundChatMessages>(
      td.SearchChatMessages(
        chatId: chatId,
        query: query,
        fromMessageId: fromMessageId,
        offset: 0,
        limit: limit,
        filter: filter,
        messageThreadId: 0,
        savedMessagesTopicId: 0,
      ),
    );
    return found.messages;
  }

  Future<List<td.Message>> scheduled(int chatId) async {
    final result = await _client.invoke<td.Messages>(td.GetChatScheduledMessages(chatId: chatId));
    return result.messages;
  }

  Future<void> saveDraft(
    int chatId,
    String text, {
    List<td.TextEntity> entities = const [],
    int? replyToMessageId,
  }) => _client.invoke<td.Ok>(
    td.SetChatDraftMessage(
      chatId: chatId,
      messageThreadId: 0,
      draftMessage: text.trim().isEmpty && replyToMessageId == null
          ? null
          : td.DraftMessage(
              replyTo: replyToMessageId == null
                  ? null
                  : td.InputMessageReplyToMessage(messageId: replyToMessageId),
              date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              inputMessageText: td.InputMessageText(
                text: td.FormattedText(text: text, entities: entities),
                clearDraft: false,
              ),
              effectId: 0,
            ),
    ),
  );

  Future<List<td.ReactionType>> availableReactions(int chatId, int messageId) async {
    final result = await _client.invoke<td.AvailableReactions>(
      td.GetMessageAvailableReactions(chatId: chatId, messageId: messageId, rowSize: 8),
    );
    return [
      for (final r in [...result.topReactions, ...result.recentReactions, ...result.popularReactions])
        if (!r.needsPremium && r.type is td.ReactionTypeEmoji) r.type,
    ].fold<List<td.ReactionType>>([], (list, r) {
      final emoji = (r as td.ReactionTypeEmoji).emoji;
      if (!list.any((x) => (x as td.ReactionTypeEmoji).emoji == emoji)) list.add(r);
      return list;
    });
  }

  Future<void> react(int chatId, int messageId, td.ReactionType reaction, {required bool add}) => add
      ? _client.invoke<td.Ok>(
          td.AddMessageReaction(
            chatId: chatId,
            messageId: messageId,
            reactionType: reaction,
            isBig: false,
            updateRecentReactions: true,
          ),
        )
      : _client.invoke<td.Ok>(
          td.RemoveMessageReaction(chatId: chatId, messageId: messageId, reactionType: reaction),
        );

  /// Typing / recording indicator, suppressed when the user hides typing.
  Future<void> sendAction(int chatId, td.ChatAction? action) async {
    if (_prefs.hideTyping) return;
    await _client.invoke<td.Ok>(
      td.SendChatAction(chatId: chatId, messageThreadId: 0, businessConnectionId: '', action: action),
    );
  }

  Future<String> link(int chatId, int messageId) async {
    final link = await _client.invoke<td.MessageLink>(
      td.GetMessageLink(
        chatId: chatId,
        messageId: messageId,
        mediaTimestamp: 0,
        forAlbum: false,
        inMessageThread: false,
      ),
    );
    return link.link;
  }

  Future<td.MessageProperties> properties(int chatId, int messageId) =>
      _client.invoke<td.MessageProperties>(td.GetMessageProperties(chatId: chatId, messageId: messageId));

  Future<List<td.SponsoredMessage>> sponsored(int chatId) async {
    final result = await _client.invoke<td.SponsoredMessages>(td.GetChatSponsoredMessages(chatId: chatId));
    return result.messages;
  }

  /// Ad impressions are always reported (they are not read receipts).
  Future<void> viewSponsored(int chatId, int messageId) =>
      _client.invoke<td.Ok>(td.ViewMessages(chatId: chatId, messageIds: [messageId], forceRead: true));

  Future<void> clickSponsored(int chatId, int messageId) =>
      _client.invoke<td.Ok>(td.ClickChatSponsoredMessage(chatId: chatId, messageId: messageId));

  /// Official ad toggle (Premium accounts).
  Future<void> setSponsoredEnabled(bool enabled) =>
      _client.invoke<td.Ok>(td.ToggleHasSponsoredMessagesEnabled(hasSponsoredMessagesEnabled: enabled));

  /// Marks a self-destructing / view-once message as opened.
  Future<void> openContent(int chatId, int messageId) =>
      _client.invoke<td.Ok>(td.OpenMessageContent(chatId: chatId, messageId: messageId));
}
