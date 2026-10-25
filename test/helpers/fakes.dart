import 'dart:async';

import 'package:lumina_tdlib/api.dart' as td;
import 'package:lumina/core/config/app_config.dart';
import 'package:lumina/core/storage/secure_store.dart';
import 'package:lumina/core/tdlib/td_client.dart';
import 'package:lumina/core/tdlib/td_errors.dart';
import 'package:lumina/core/tdlib/td_paths.dart';
import 'package:lumina/features/auth/data/auth_repository.dart';

/// Scriptable [TdClient]: records every invoke and answers through [respond].
class FakeTdClient implements TdClient {
  final _updates = StreamController<td.Update>.broadcast();
  final sent = <td.TdFunction>[];
  FutureOr<td.TdObject> Function(td.TdFunction function) respond = (_) => const td.Ok();

  /// Answers for background requests made by app services (proxy restore),
  /// applied before [respond].
  td.TdObject? _builtIn(td.TdFunction f) => switch (f) {
    td.GetProxies() => const td.AddedProxies(proxies: []),
    _ => null,
  };
  var starts = 0;
  var recreations = 0;

  void emit(td.AuthorizationState state) =>
      _updates.add(td.UpdateAuthorizationState(authorizationState: state));

  void emitUpdate(td.Update update) => _updates.add(update);

  List<T> sentOf<T extends td.TdFunction>() => sent.whereType<T>().toList();

  @override
  Stream<td.Update> get updates => _updates.stream;

  @override
  int? get clientId => 1;

  @override
  Future<void> start() async => starts++;

  @override
  Future<T> invoke<T extends td.TdObject>(td.TdFunction function, {Duration? timeout}) async {
    sent.add(function);
    final result = _builtIn(function) ?? await respond(function);
    if (result is td.TdError) throw TdException(result.code, result.message);
    return result as T;
  }

  @override
  Future<td.TdObject?> execute(td.TdFunction function) async => const td.Ok();

  @override
  Future<void> recreateAfterClose() async => recreations++;

  @override
  Future<void> ensureReceiving() async {}

  @override
  Future<void> dispose() => _updates.close();
}

class FakeSecureStore extends SecureStore {
  String? key = 'a2V5';
  var discards = 0;

  @override
  Future<String> databaseEncryptionKey() async => key ??= 'bmV3';

  @override
  Future<void> discardDatabaseEncryptionKey() async {
    key = null;
    discards++;
  }

  final secrets = <String, String>{};

  @override
  Future<String?> readSecret(String key) async => secrets[key];

  @override
  Future<void> writeSecret(String key, String? value) async =>
      value == null ? secrets.remove(key) : secrets[key] = value;
}

class FakePaths extends TdPaths {
  FakePaths() : super('/data/user/0/dev.lumina/files/tdlib/db', '/data/user/0/dev.lumina/files/tdlib/files');
  var wipes = 0;

  @override
  Future<void> wipe() async => wipes++;
}

td.User fakeUser({bool bot = false}) => td.User(
  id: 42,
  firstName: bot ? 'Echo Bot' : 'Ada',
  lastName: bot ? '' : 'Lovelace',
  phoneNumber: bot ? '' : '447700900000',
  status: const td.UserStatusEmpty(),
  accentColorId: 0,
  backgroundCustomEmojiId: 0,
  profileAccentColorId: -1,
  profileBackgroundCustomEmojiId: 0,
  isContact: false,
  isMutualContact: false,
  isCloseFriend: false,
  isPremium: false,
  isSupport: false,
  restrictsNewChats: false,
  paidMessageStarCount: 0,
  haveAccess: true,
  type: bot
      ? const td.UserTypeBot(
          canBeEdited: true,
          canJoinGroups: true,
          canReadAllGroupMessages: false,
          hasMainWebApp: false,
          hasTopics: false,
          allowsUsersToCreateTopics: false,
          canManageBots: false,
          isInline: false,
          inlineQueryPlaceholder: '',
          supportsGuestQueries: false,
          isGuard: false,
          needLocation: false,
          canConnectToBusiness: false,
          canBeAddedToAttachmentMenu: false,
          activeUserCount: 0,
        )
      : const td.UserTypeRegular(),
  languageCode: 'en',
  addedToAttachmentMenu: false,
);

const smsCodeInfo = td.AuthenticationCodeInfo(
  phoneNumber: '+447700900000',
  type: td.AuthenticationCodeTypeSms(length: 5),
  timeout: 60,
);

/// Lets queued listeners and async handlers run.
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Real [AuthRepository] over the fakes, so bloc tests also cover the
/// repository's TDLib requests.
class AuthHarness {
  AuthHarness({TdSettings settings = const TdSettings(apiId: 1, apiHash: 'hash')}) {
    repository = AuthRepository(client: client, secureStore: secure, paths: paths, settings: settings);
  }

  final client = FakeTdClient();
  final secure = FakeSecureStore();
  final paths = FakePaths();
  late final AuthRepository repository;
}

td.Chat fakeChat(int id, {String title = 'Chat', int order = 0, int unread = 0, td.Message? lastMessage}) =>
    td.Chat(
      id: id,
      type: td.ChatTypePrivate(userId: id),
      title: title,
      accentColorId: 0,
      backgroundCustomEmojiId: 0,
      profileAccentColorId: -1,
      profileBackgroundCustomEmojiId: 0,
      permissions: const td.ChatPermissions(
        canSendBasicMessages: true,
        canSendAudios: true,
        canSendDocuments: true,
        canSendPhotos: true,
        canSendVideos: true,
        canSendVideoNotes: true,
        canSendVoiceNotes: true,
        canSendPolls: true,
        canSendOtherMessages: true,
        canAddLinkPreviews: true,
        canReactToMessages: true,
        canEditTag: true,
        canChangeInfo: true,
        canInviteUsers: true,
        canPinMessages: true,
        canCreateTopics: true,
      ),
      lastMessage: lastMessage,
      positions: [
        if (order != 0) td.ChatPosition(list: const td.ChatListMain(), order: order, isPinned: false),
      ],
      chatLists: const [],
      hasProtectedContent: false,
      isTranslatable: false,
      isMarkedAsUnread: false,
      viewAsTopics: false,
      hasScheduledMessages: false,
      hasWelcomeMessages: false,
      canBeDeletedOnlyForSelf: true,
      canBeDeletedForAllUsers: true,
      canBeReported: false,
      defaultDisableNotification: false,
      unreadCount: unread,
      lastReadInboxMessageId: 0,
      lastReadOutboxMessageId: 0,
      unreadMentionCount: 0,
      unreadReactionCount: 0,
      unreadPollVoteCount: 0,
      notificationSettings: const td.ChatNotificationSettings(
        useDefaultMuteFor: true,
        muteFor: 0,
        useDefaultSound: true,
        soundId: 0,
        useDefaultShowPreview: true,
        showPreview: true,
        useDefaultMuteStories: true,
        muteStories: false,
        useDefaultStorySound: true,
        storySoundId: 0,
        useDefaultShowStoryPoster: true,
        showStoryPoster: true,
        useDefaultDisablePinnedMessageNotifications: true,
        disablePinnedMessageNotifications: false,
        useDefaultDisableMentionNotifications: true,
        disableMentionNotifications: false,
      ),
      availableReactions: const td.ChatAvailableReactionsAll(maxReactionCount: 11),
      messageAutoDeleteTime: 0,
      videoChat: const td.VideoChat(groupCallId: 0, hasParticipants: false),
      replyMarkupMessageId: 0,
      clientData: '',
    );

td.Message fakeMessage(
  int id, {
  int chatId = 1,
  int senderUserId = 7,
  bool outgoing = false,
  int date = 1761390000,
  int albumId = 0,
  String text = 'hi',
  td.MessageContent? content,
}) => td.Message(
  id: id,
  senderId: td.MessageSenderUser(userId: senderUserId),
  chatId: chatId,
  isOutgoing: outgoing,
  isPinned: false,
  isFromOffline: false,
  canBeSaved: true,
  hasTimestampedMedia: false,
  isChannelPost: false,
  isPaidStarSuggestedPost: false,
  isPaidGramSuggestedPost: false,
  containsUnreadMention: false,
  containsUnreadPollVotes: false,
  date: date,
  editDate: 0,
  unreadReactions: const [],
  selfDestructIn: 0,
  autoDeleteIn: 0,
  viaBotUserId: 0,
  senderBusinessBotUserId: 0,
  senderBoostCount: 0,
  senderTag: '',
  paidMessageStarCount: 0,
  authorSignature: '',
  mediaAlbumId: albumId,
  effectId: 0,
  summaryLanguageCode: '',
  ephemeralMessageId: 0,
  chatInstance: 0,
  content:
      content ??
      td.MessageText(
        text: td.FormattedText(text: text, entities: const []),
      ),
);
