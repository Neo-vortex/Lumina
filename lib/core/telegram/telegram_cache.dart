import 'dart:async';

import 'package:lumina_tdlib/api.dart' as td;

import '../tdlib/td_client.dart';

/// What changed in the [TelegramCache]. Listeners filter by kind/id so a
/// burst of updates only wakes the widgets that show the affected entity.
sealed class CacheEvent {
  const CacheEvent();
}

final class ChatChanged extends CacheEvent {
  const ChatChanged(this.chatId, {this.orderChanged = false});
  final int chatId;

  /// The chat's position in a list moved (new message, pin, archive).
  final bool orderChanged;
}

final class UserChanged extends CacheEvent {
  const UserChanged(this.userId);
  final int userId;
}

final class GroupChanged extends CacheEvent {
  const GroupChanged({this.basicGroupId, this.supergroupId});
  final int? basicGroupId;
  final int? supergroupId;
}

final class SecretChatChanged extends CacheEvent {
  const SecretChatChanged(this.secretChatId);
  final int secretChatId;
}

final class TypingChanged extends CacheEvent {
  const TypingChanged(this.chatId);
  final int chatId;
}

final class ConnectionChanged extends CacheEvent {
  const ConnectionChanged();
}

/// App-wide mirror of the TDLib entities that many screens need: chats,
/// users, groups, secret chats, chat actions and the connection state.
///
/// TDLib guarantees every entity is announced through an update before it is
/// referenced, so this is a pure projection of the update stream. Messages
/// are deliberately not mirrored (spec §3.4); conversations load them on
/// demand and TDLib keeps them in its own database.
class TelegramCache {
  TelegramCache(TdClient client) {
    _subscription = client.updates.listen(apply);
  }

  /// For tests: a cache fed manually through [apply].
  TelegramCache.detached();

  StreamSubscription<td.Update>? _subscription;
  final _events = StreamController<CacheEvent>.broadcast(sync: true);

  final chats = <int, td.Chat>{};
  final users = <int, td.User>{};
  final basicGroups = <int, td.BasicGroup>{};
  final supergroups = <int, td.Supergroup>{};
  final secretChats = <int, td.SecretChat>{};

  /// Default mute duration per chat type (private, group, channel), for
  /// chats whose settings say "use the default".
  final _scopeMuteFor = <Type, int>{};

  /// chatId -> sender key -> action. Entries expire after 6 s without a
  /// refresh, as TDLib clients are expected to do.
  final _typing = <int, Map<String, ({td.MessageSender sender, td.ChatAction action, Timer expiry})>>{};

  td.ConnectionState connectionState = const td.ConnectionStateConnecting();

  Stream<CacheEvent> get events => _events.stream;

  void apply(td.Update update) {
    switch (update) {
      case td.UpdateNewChat(:final chat):
        chats[chat.id] = chat;
        _emit(ChatChanged(chat.id, orderChanged: true));
      case td.UpdateChatTitle(:final chatId, :final title):
        _patchChat(chatId, (c) => c.copyWith(title: title));
      case td.UpdateChatPhoto(:final chatId, :final photo):
        _patchChat(chatId, (c) => _withPhoto(c, photo));
      case td.UpdateChatLastMessage(:final chatId, :final lastMessage, :final positions):
        _patchChat(chatId, (c) {
          var next = _withLastMessage(c, lastMessage);
          for (final p in positions) {
            next = _withPosition(next, p);
          }
          return next;
        }, orderChanged: true);
      case td.UpdateChatPosition(:final chatId, :final position):
        _patchChat(chatId, (c) => _withPosition(c, position), orderChanged: true);
      case td.UpdateChatReadInbox(:final chatId, :final lastReadInboxMessageId, :final unreadCount):
        _patchChat(
          chatId,
          (c) => c.copyWith(lastReadInboxMessageId: lastReadInboxMessageId, unreadCount: unreadCount),
        );
      case td.UpdateChatReadOutbox(:final chatId, :final lastReadOutboxMessageId):
        _patchChat(chatId, (c) => c.copyWith(lastReadOutboxMessageId: lastReadOutboxMessageId));
      case td.UpdateChatDraftMessage(:final chatId, :final draftMessage, :final positions):
        _patchChat(chatId, (c) {
          var next = _withDraft(c, draftMessage);
          for (final p in positions) {
            next = _withPosition(next, p);
          }
          return next;
        }, orderChanged: true);
      case td.UpdateChatUnreadMentionCount(:final chatId, :final unreadMentionCount):
        _patchChat(chatId, (c) => c.copyWith(unreadMentionCount: unreadMentionCount));
      case td.UpdateChatIsMarkedAsUnread(:final chatId, :final isMarkedAsUnread):
        _patchChat(chatId, (c) => c.copyWith(isMarkedAsUnread: isMarkedAsUnread));
      case td.UpdateChatPermissions(:final chatId, :final permissions):
        _patchChat(chatId, (c) => c.copyWith(permissions: permissions));
      case td.UpdateChatNotificationSettings(:final chatId, :final notificationSettings):
        _patchChat(chatId, (c) => c.copyWith(notificationSettings: notificationSettings));
      case td.UpdateScopeNotificationSettings(:final scope, :final notificationSettings):
        _scopeMuteFor[scope.runtimeType] = notificationSettings.muteFor;
        for (final c in chats.values) {
          if (c.notificationSettings.useDefaultMuteFor && _scopeOf(c).runtimeType == scope.runtimeType) {
            _emit(ChatChanged(c.id));
          }
        }
      case td.UpdateChatAvailableReactions(:final chatId, :final availableReactions):
        _patchChat(chatId, (c) => c.copyWith(availableReactions: availableReactions));
      case td.UpdateChatHasScheduledMessages(:final chatId, :final hasScheduledMessages):
        _patchChat(chatId, (c) => c.copyWith(hasScheduledMessages: hasScheduledMessages));
      case td.UpdateUser(:final user):
        users[user.id] = user;
        _emit(UserChanged(user.id));
      case td.UpdateUserStatus(:final userId, :final status):
        final user = users[userId];
        if (user != null) {
          users[userId] = user.copyWith(status: status);
          _emit(UserChanged(userId));
        }
      case td.UpdateBasicGroup(:final basicGroup):
        basicGroups[basicGroup.id] = basicGroup;
        _emit(GroupChanged(basicGroupId: basicGroup.id));
      case td.UpdateSupergroup(:final supergroup):
        supergroups[supergroup.id] = supergroup;
        _emit(GroupChanged(supergroupId: supergroup.id));
      case td.UpdateSecretChat(:final secretChat):
        secretChats[secretChat.id] = secretChat;
        _emit(SecretChatChanged(secretChat.id));
      case td.UpdateChatAction(:final chatId, :final topicId, :final senderId, :final action):
        if (topicId == null) _onChatAction(chatId, senderId, action);
      case td.UpdateAuthorizationState(authorizationState: td.AuthorizationStateClosed()):
        clear();
      case td.UpdateConnectionState(:final state):
        connectionState = state;
        _emit(const ConnectionChanged());
      default:
        break;
    }
  }

  // ---- Queries --------------------------------------------------------------

  /// Chats in [list] in TDLib's order (descending `order`, then id).
  List<td.Chat> chatsIn(td.ChatList list) {
    final entries = <(int, td.Chat)>[];
    for (final chat in chats.values) {
      for (final position in chat.positions) {
        if (_sameList(position.list, list) && position.order != 0) {
          entries.add((position.order, chat));
          break;
        }
      }
    }
    entries.sort((a, b) {
      final byOrder = b.$1.compareTo(a.$1);
      return byOrder != 0 ? byOrder : b.$2.id.compareTo(a.$2.id);
    });
    return [for (final e in entries) e.$2];
  }

  td.ChatPosition? positionIn(td.Chat chat, td.ChatList list) {
    for (final p in chat.positions) {
      if (_sameList(p.list, list)) return p;
    }
    return null;
  }

  /// Senders currently performing an action in [chatId] (typing, recording…).
  List<({td.MessageSender sender, td.ChatAction action})> actionsIn(int chatId) => [
    for (final e in (_typing[chatId] ?? const {}).values) (sender: e.sender, action: e.action),
  ];

  /// The user on the other side of a private or secret chat.
  td.User? peerUser(td.Chat chat) => switch (chat.type) {
    td.ChatTypePrivate(:final userId) => users[userId],
    td.ChatTypeSecret(:final userId) => users[userId],
    _ => null,
  };

  td.Supergroup? supergroupOf(td.Chat chat) => switch (chat.type) {
    td.ChatTypeSupergroup(:final supergroupId) => supergroups[supergroupId],
    _ => null,
  };

  td.BasicGroup? basicGroupOf(td.Chat chat) => switch (chat.type) {
    td.ChatTypeBasicGroup(:final basicGroupId) => basicGroups[basicGroupId],
    _ => null,
  };

  /// The chat is in the main list only because the active MTProto proxy
  /// sponsors it.
  bool isProxySponsored(td.Chat chat) =>
      positionIn(chat, const td.ChatListMain())?.source is td.ChatSourceMtprotoProxy;

  bool isChannel(td.Chat chat) =>
      chat.type is td.ChatTypeSupergroup && (chat.type as td.ChatTypeSupergroup).isChannel;

  /// Whether the chat's notifications are muted, following the chat-type
  /// default when the chat has no explicit setting.
  bool isMuted(td.Chat chat) {
    final settings = chat.notificationSettings;
    final muteFor = settings.useDefaultMuteFor
        ? _scopeMuteFor[_scopeOf(chat).runtimeType] ?? 0
        : settings.muteFor;
    return muteFor > 0;
  }

  td.NotificationSettingsScope _scopeOf(td.Chat chat) => switch (chat.type) {
    td.ChatTypePrivate() || td.ChatTypeSecret() => const td.NotificationSettingsScopePrivateChats(),
    td.ChatTypeSupergroup(isChannel: true) => const td.NotificationSettingsScopeChannelChats(),
    _ => const td.NotificationSettingsScopeGroupChats(),
  };

  /// Forgets everything; called when the session closes.
  void clear() {
    chats.clear();
    _scopeMuteFor.clear();
    users.clear();
    basicGroups.clear();
    supergroups.clear();
    secretChats.clear();
    for (final perChat in _typing.values) {
      for (final e in perChat.values) {
        e.expiry.cancel();
      }
    }
    _typing.clear();
  }

  Future<void> dispose() async {
    clear();
    await _subscription?.cancel();
    await _events.close();
  }

  // ---- Internals ------------------------------------------------------------

  void _emit(CacheEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _patchChat(int chatId, td.Chat Function(td.Chat) patch, {bool orderChanged = false}) {
    final chat = chats[chatId];
    if (chat == null) return;
    chats[chatId] = patch(chat);
    _emit(ChatChanged(chatId, orderChanged: orderChanged));
  }

  void _onChatAction(int chatId, td.MessageSender sender, td.ChatAction action) {
    final key = switch (sender) {
      td.MessageSenderUser(:final userId) => 'u$userId',
      td.MessageSenderChat(:final chatId) => 'c$chatId',
    };
    final perChat = _typing.putIfAbsent(chatId, () => {});
    perChat.remove(key)?.expiry.cancel();
    if (action is! td.ChatActionCancel) {
      perChat[key] = (
        sender: sender,
        action: action,
        expiry: Timer(const Duration(seconds: 6), () {
          perChat.remove(key);
          _emit(TypingChanged(chatId));
        }),
      );
    }
    _emit(TypingChanged(chatId));
  }

  static bool _sameList(td.ChatList a, td.ChatList b) => switch ((a, b)) {
    (td.ChatListMain(), td.ChatListMain()) => true,
    (td.ChatListArchive(), td.ChatListArchive()) => true,
    (td.ChatListFolder(chatFolderId: final x), td.ChatListFolder(chatFolderId: final y)) => x == y,
    _ => false,
  };

  static td.Chat _withPosition(td.Chat chat, td.ChatPosition position) {
    final positions = [
      for (final p in chat.positions)
        if (!_sameList(p.list, position.list)) p,
      if (position.order != 0) position,
    ];
    return chat.copyWith(positions: positions);
  }

  // copyWith cannot set a field back to null; rebuild for nullable ones.
  static td.Chat _withLastMessage(td.Chat c, td.Message? lastMessage) =>
      lastMessage != null ? c.copyWith(lastMessage: lastMessage) : _rebuild(c, clearLastMessage: true);

  static td.Chat _withDraft(td.Chat c, td.DraftMessage? draft) =>
      draft != null ? c.copyWith(draftMessage: draft) : _rebuild(c, clearDraft: true);

  static td.Chat _withPhoto(td.Chat c, td.ChatPhotoInfo? photo) =>
      photo != null ? c.copyWith(photo: photo) : _rebuild(c, clearPhoto: true);

  static td.Chat _rebuild(
    td.Chat c, {
    bool clearLastMessage = false,
    bool clearDraft = false,
    bool clearPhoto = false,
  }) => td.Chat(
    id: c.id,
    type: c.type,
    title: c.title,
    photo: clearPhoto ? null : c.photo,
    accentColorId: c.accentColorId,
    backgroundCustomEmojiId: c.backgroundCustomEmojiId,
    upgradedGiftColors: c.upgradedGiftColors,
    profileAccentColorId: c.profileAccentColorId,
    profileBackgroundCustomEmojiId: c.profileBackgroundCustomEmojiId,
    permissions: c.permissions,
    lastMessage: clearLastMessage ? null : c.lastMessage,
    positions: c.positions,
    chatLists: c.chatLists,
    messageSenderId: c.messageSenderId,
    blockList: c.blockList,
    hasProtectedContent: c.hasProtectedContent,
    isTranslatable: c.isTranslatable,
    isMarkedAsUnread: c.isMarkedAsUnread,
    viewAsTopics: c.viewAsTopics,
    hasScheduledMessages: c.hasScheduledMessages,
    hasWelcomeMessages: c.hasWelcomeMessages,
    canBeDeletedOnlyForSelf: c.canBeDeletedOnlyForSelf,
    canBeDeletedForAllUsers: c.canBeDeletedForAllUsers,
    canBeReported: c.canBeReported,
    defaultDisableNotification: c.defaultDisableNotification,
    unreadCount: c.unreadCount,
    lastReadInboxMessageId: c.lastReadInboxMessageId,
    lastReadOutboxMessageId: c.lastReadOutboxMessageId,
    unreadMentionCount: c.unreadMentionCount,
    unreadReactionCount: c.unreadReactionCount,
    unreadPollVoteCount: c.unreadPollVoteCount,
    notificationSettings: c.notificationSettings,
    availableReactions: c.availableReactions,
    messageAutoDeleteTime: c.messageAutoDeleteTime,
    emojiStatus: c.emojiStatus,
    background: c.background,
    theme: c.theme,
    actionBar: c.actionBar,
    businessBotManageBar: c.businessBotManageBar,
    videoChat: c.videoChat,
    pendingJoinRequests: c.pendingJoinRequests,
    replyMarkupMessageId: c.replyMarkupMessageId,
    draftMessage: clearDraft ? null : c.draftMessage,
    clientData: c.clientData,
  );
}
