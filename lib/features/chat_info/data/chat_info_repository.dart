import 'package:handy_tdlib_next/api.dart' as td;

import '../../../core/tdlib/td_client.dart';
import '../../../core/tdlib/td_errors.dart';
import '../../../core/telegram/telegram_cache.dart';

/// What the chat info screen shows, regardless of chat type.
class ChatDetails {
  const ChatDetails({
    this.description = '',
    this.memberCount = 0,
    this.inviteLink,
    this.linkedChatId = 0,
    this.slowModeDelay = 0,
    this.canGetMembers = false,
    this.basicMembers = const [],
    this.isAllHistoryAvailable = true,
    this.user,
    this.userFull,
  });

  final String description;
  final int memberCount;
  final td.ChatInviteLink? inviteLink;

  /// Channel ↔ discussion group link (spec §6.3).
  final int linkedChatId;
  final int slowModeDelay;
  final bool canGetMembers;
  final List<td.ChatMember> basicMembers;
  final bool isAllHistoryAvailable;
  final td.User? user;
  final td.UserFullInfo? userFull;
}

/// Group, channel and private-chat management (spec §6.2 / §6.3).
class ChatInfoRepository {
  ChatInfoRepository({required this._client, required this._cache});

  final TdClient _client;
  final TelegramCache _cache;

  TelegramCache get cache => _cache;

  Future<ChatDetails> details(td.Chat chat) async {
    switch (chat.type) {
      case td.ChatTypeSupergroup(:final supergroupId):
        final f = await _client.invoke<td.SupergroupFullInfo>(td.GetSupergroupFullInfo(supergroupId: supergroupId));
        return ChatDetails(
          description: f.description,
          memberCount: f.memberCount,
          inviteLink: f.inviteLink,
          linkedChatId: f.linkedChatId,
          slowModeDelay: f.slowModeDelay,
          canGetMembers: f.canGetMembers,
          isAllHistoryAvailable: f.isAllHistoryAvailable,
        );
      case td.ChatTypeBasicGroup(:final basicGroupId):
        final f = await _client.invoke<td.BasicGroupFullInfo>(td.GetBasicGroupFullInfo(basicGroupId: basicGroupId));
        return ChatDetails(
          description: f.description,
          memberCount: f.members.length,
          inviteLink: f.inviteLink,
          canGetMembers: true,
          basicMembers: f.members,
        );
      case td.ChatTypePrivate(:final userId) || td.ChatTypeSecret(:final userId):
        final full = await _client.invoke<td.UserFullInfo>(td.GetUserFullInfo(userId: userId));
        return ChatDetails(
          description: full.bio?.text ?? full.botInfo?.description ?? '',
          user: _cache.users[userId],
          userFull: full,
        );
    }
  }

  Future<List<td.ChatMember>> members(
    td.Chat chat, {
    String query = '',
    bool adminsOnly = false,
    int offset = 0,
  }) async {
    switch (chat.type) {
      case td.ChatTypeSupergroup(:final supergroupId):
        final filter = adminsOnly
            ? const td.SupergroupMembersFilterAdministrators()
            : query.isEmpty
            ? const td.SupergroupMembersFilterRecent()
            : td.SupergroupMembersFilterSearch(query: query);
        final r = await _client.invoke<td.ChatMembers>(
          td.GetSupergroupMembers(supergroupId: supergroupId, filter: filter, offset: offset, limit: 100),
        );
        return r.members;
      case td.ChatTypeBasicGroup():
        final d = await details(chat);
        final q = query.toLowerCase();
        return d.basicMembers.where((m) {
          if (adminsOnly && m.status is! td.ChatMemberStatusAdministrator && m.status is! td.ChatMemberStatusCreator) {
            return false;
          }
          if (q.isEmpty) return true;
          final id = switch (m.memberId) {
            td.MessageSenderUser(:final userId) => userId,
            td.MessageSenderChat(:final chatId) => chatId,
          };
          final u = _cache.users[id];
          return '${u?.firstName} ${u?.lastName}'.toLowerCase().contains(q);
        }).toList();
      default:
        return const [];
    }
  }

  Future<void> addMembers(td.Chat chat, List<int> userIds) async {
    if (chat.type is td.ChatTypeBasicGroup) {
      for (final id in userIds) {
        await _client.invoke<td.Ok>(td.AddChatMember(chatId: chat.id, userId: id, forwardLimit: 100));
      }
    } else {
      await _client.invoke<td.Ok>(td.AddChatMembers(chatId: chat.id, userIds: userIds));
    }
  }

  Future<void> removeMember(td.Chat chat, td.MessageSender member) => _client.invoke<td.Ok>(
    td.BanChatMember(chatId: chat.id, memberId: member, bannedUntilDate: 0, revokeMessages: false),
  );

  /// Admin rights editor; null [rights] demotes to a regular member.
  Future<void> setAdmin(td.Chat chat, int userId, td.ChatAdministratorRights? rights, {String title = ''}) =>
      _client.invoke<td.Ok>(
        td.SetChatMemberStatus(
          chatId: chat.id,
          memberId: td.MessageSenderUser(userId: userId),
          status: rights == null
              ? const td.ChatMemberStatusMember(memberUntilDate: 0)
              : td.ChatMemberStatusAdministrator(customTitle: title, canBeEdited: true, rights: rights),
        ),
      );

  Future<void> setPermissions(td.Chat chat, td.ChatPermissions p) =>
      _client.invoke<td.Ok>(td.SetChatPermissions(chatId: chat.id, permissions: p));

  /// Slow mode delay in seconds: 0, 10, 30, 60, 300, 900 or 3600.
  Future<void> setSlowMode(td.Chat chat, int seconds) =>
      _client.invoke<td.Ok>(td.SetChatSlowModeDelay(chatId: chat.id, slowModeDelay: seconds));

  Future<void> setTitle(td.Chat chat, String title) =>
      _client.invoke<td.Ok>(td.SetChatTitle(chatId: chat.id, title: title));

  Future<void> setDescription(td.Chat chat, String text) =>
      _client.invoke<td.Ok>(td.SetChatDescription(chatId: chat.id, description: text));

  Future<td.ChatInviteLink> newInviteLink(
    td.Chat chat, {
    String name = '',
    int memberLimit = 0,
    bool requestApproval = false,
  }) => _client.invoke<td.ChatInviteLink>(
    td.CreateChatInviteLink(
      chatId: chat.id,
      name: name,
      expirationDate: 0,
      memberLimit: memberLimit,
      createsJoinRequest: requestApproval,
    ),
  );

  Future<td.ChatInviteLink> replacePrimaryLink(td.Chat chat) =>
      _client.invoke<td.ChatInviteLink>(td.ReplacePrimaryChatInviteLink(chatId: chat.id));

  Future<void> join(td.Chat chat) => _client.invoke<td.Ok>(td.JoinChat(chatId: chat.id));

  Future<List<int>> contacts() async => (await _client.invoke<td.Users>(const td.GetContacts())).userIds;

  Future<List<int>> searchContacts(String query) async =>
      (await _client.invoke<td.Users>(td.SearchContacts(query: query, limit: 50))).userIds;

  /// A user by @username (for new chats / adding members not in contacts).
  Future<int?> findUser(String username) async {
    try {
      final chat = await _client.invoke<td.Chat>(td.SearchPublicChat(username: username.replaceFirst('@', '')));
      return switch (chat.type) {
        td.ChatTypePrivate(:final userId) => userId,
        _ => null,
      };
    } on TdException {
      return null;
    }
  }

  Future<td.Chat> createGroup(String title, List<int> userIds) async {
    final created = await _client.invoke<td.CreatedBasicGroupChat>(
      td.CreateNewBasicGroupChat(userIds: userIds, title: title, messageAutoDeleteTime: 0),
    );
    return _client.invoke<td.Chat>(td.GetChat(chatId: created.chatId));
  }

  Future<td.Chat> createChannel(String title, String description) => _client.invoke<td.Chat>(
    td.CreateNewSupergroupChat(
      title: title,
      isForum: false,
      isChannel: true,
      description: description,
      messageAutoDeleteTime: 0,
      forImport: false,
    ),
  );

  /// End-to-end encrypted chat (users only; forbidden for bots, spec §6.1).
  Future<td.Chat> createSecretChat(int userId) => _client.invoke<td.Chat>(td.CreateNewSecretChat(userId: userId));

  Future<td.Chat> privateChat(int userId) =>
      _client.invoke<td.Chat>(td.CreatePrivateChat(userId: userId, force: false));
}
