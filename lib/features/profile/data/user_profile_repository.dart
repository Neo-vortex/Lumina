import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/tdlib/td_client.dart';

/// The shared-content tabs on a user's profile.
enum ProfileTab {
  media('Media', td.SearchMessagesFilterPhotoAndVideo()),
  files('Files', td.SearchMessagesFilterDocument()),
  links('Links', td.SearchMessagesFilterUrl()),
  music('Music', td.SearchMessagesFilterAudio()),
  voice('Voice', td.SearchMessagesFilterVoiceAndVideoNote()),
  gifs('GIFs', td.SearchMessagesFilterAnimation()),
  gifts('Gifts', null),
  groups('Groups', null);

  const ProfileTab(this.label, this.filter);

  final String label;

  /// The message search behind the tab; null for gifts and groups.
  final td.SearchMessagesFilter? filter;
}

/// Everything TDLib offers about a user, plus the profile's actions.
class UserProfileRepository {
  UserProfileRepository(this._client);

  final TdClient _client;

  Future<td.UserFullInfo> fullInfo(int userId) =>
      _client.invoke<td.UserFullInfo>(td.GetUserFullInfo(userId: userId));

  Future<List<td.ChatPhoto>> photos(int userId) async =>
      (await _client.invoke<td.ChatPhotos>(td.GetUserProfilePhotos(userId: userId, offset: 0, limit: 50)))
          .photos;

  /// Their stories posted to the profile ("Posts").
  Future<List<td.Story>> posts(int userId) async => (await _client.invoke<td.Stories>(
    td.GetChatPostedToChatPageStories(chatId: userId, fromStoryId: 0, limit: 30),
  )).stories;

  /// A page of [tab]'s messages in the private chat, newest first.
  Future<List<td.Message>> shared(int chatId, ProfileTab tab, {int fromMessageId = 0}) async {
    final found = await _client.invoke<td.FoundChatMessages>(
      td.SearchChatMessages(
        chatId: chatId,
        query: '',
        fromMessageId: fromMessageId,
        offset: 0,
        limit: 50,
        filter: tab.filter,
      ),
    );
    return found.messages;
  }

  Future<List<td.ReceivedGift>> gifts(int userId) async => (await _client.invoke<td.ReceivedGifts>(
    td.GetReceivedGifts(
      businessConnectionId: '',
      ownerId: td.MessageSenderUser(userId: userId),
      collectionId: 0,
      excludeUnsaved: false,
      excludeSaved: false,
      excludeUnlimited: false,
      excludeUpgradable: false,
      excludeNonUpgradable: false,
      excludeUpgraded: false,
      excludeWithoutColors: false,
      excludeHosted: false,
      sortByPrice: false,
      offset: '',
      limit: 100,
    ),
  )).gifts;

  Future<List<int>> groupsInCommon(int userId) async =>
      (await _client.invoke<td.Chats>(td.GetGroupsInCommon(userId: userId, offsetChatId: 0, limit: 100)))
          .chatIds;

  Future<void> setBlocked(int userId, bool blocked) => _client.invoke<td.Ok>(
    td.SetMessageSenderBlockList(
      senderId: td.MessageSenderUser(userId: userId),
      blockList: blocked ? const td.BlockListMain() : null,
    ),
  );

  Future<td.Chat> startSecretChat(int userId) =>
      _client.invoke<td.Chat>(td.CreateNewSecretChat(userId: userId));

  /// Adds or renames the contact.
  Future<void> saveContact(td.User user, {required String firstName, required String lastName}) =>
      _client.invoke<td.Ok>(
        td.AddContact(
          userId: user.id,
          contact: td.ImportedContact(
            phoneNumber: user.phoneNumber,
            firstName: firstName,
            lastName: lastName,
          ),
          sharePhoneNumber: false,
        ),
      );

  Future<void> deleteContact(int userId) => _client.invoke<td.Ok>(td.RemoveContacts(userIds: [userId]));
}
