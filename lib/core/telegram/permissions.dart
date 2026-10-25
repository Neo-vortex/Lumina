import 'package:lumina_tdlib/api.dart' as td;

import 'telegram_cache.dart';

/// What the signed-in account may do in a chat, derived from the cached
/// member status and chat permissions.
extension ChatPermissionsX on TelegramCache {
  td.ChatMemberStatus? myStatus(td.Chat chat) => supergroupOf(chat)?.status ?? basicGroupOf(chat)?.status;

  bool isAdmin(td.Chat chat) => switch (myStatus(chat)) {
    td.ChatMemberStatusCreator() || td.ChatMemberStatusAdministrator() => true,
    _ => false,
  };

  td.ChatAdministratorRights? adminRights(td.Chat chat) => switch (myStatus(chat)) {
    td.ChatMemberStatusAdministrator(:final rights) => rights,
    _ => null,
  };

  bool isMember(td.Chat chat) => switch (myStatus(chat)) {
    td.ChatMemberStatusLeft() || td.ChatMemberStatusBanned() => false,
    td.ChatMemberStatusRestricted(:final isMember) => isMember,
    td.ChatMemberStatusCreator(:final isMember) => isMember,
    _ => true,
  };

  /// Whether the composer should be enabled.
  bool canPost(td.Chat chat) {
    if (chat.type is td.ChatTypePrivate) return true;
    if (chat.type case td.ChatTypeSecret(:final secretChatId)) {
      return secretChats[secretChatId]?.state is td.SecretChatStateReady;
    }
    final status = myStatus(chat);
    if (isChannel(chat)) {
      return switch (status) {
        td.ChatMemberStatusCreator() => true,
        td.ChatMemberStatusAdministrator(:final rights) => rights.canPostMessages,
        _ => false,
      };
    }
    return switch (status) {
      td.ChatMemberStatusCreator() || td.ChatMemberStatusAdministrator() => true,
      td.ChatMemberStatusRestricted(:final permissions) => permissions.canSendBasicMessages,
      td.ChatMemberStatusLeft() || td.ChatMemberStatusBanned() => false,
      _ => chat.permissions.canSendBasicMessages,
    };
  }

  bool canSendMedia(td.Chat chat) {
    if (!canPost(chat)) return false;
    if (isAdmin(chat) || chat.type is td.ChatTypePrivate || chat.type is td.ChatTypeSecret) return true;
    final p = switch (myStatus(chat)) {
      td.ChatMemberStatusRestricted(:final permissions) => permissions,
      _ => chat.permissions,
    };
    return p.canSendPhotos || p.canSendVideos || p.canSendDocuments;
  }

  bool canSendVoice(td.Chat chat) {
    if (!canPost(chat)) return false;
    if (isAdmin(chat) || chat.type is td.ChatTypePrivate || chat.type is td.ChatTypeSecret) return true;
    final p = switch (myStatus(chat)) {
      td.ChatMemberStatusRestricted(:final permissions) => permissions,
      _ => chat.permissions,
    };
    return p.canSendVoiceNotes;
  }
}
