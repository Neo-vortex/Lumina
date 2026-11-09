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

  // ---- your own account ----------------------------------------------------

  /// Uploads [path] as the new main profile photo.
  Future<void> setProfilePhoto(String path) => _client.invoke<td.Ok>(
    td.SetProfilePhoto(
      photo: td.InputChatPhotoStatic(photo: td.InputFileLocal(path: path)),
      isPublic: false,
    ),
  );

  /// Makes one of your earlier photos the main one again.
  Future<void> setMainPhoto(int photoId) => _client.invoke<td.Ok>(
    td.SetProfilePhoto(photo: td.InputChatPhotoPrevious(chatPhotoId: photoId), isPublic: false),
  );

  Future<void> deleteProfilePhoto(int photoId) =>
      _client.invoke<td.Ok>(td.DeleteProfilePhoto(profilePhotoId: photoId));

  Future<void> setName(String firstName, String lastName) =>
      _client.invoke<td.Ok>(td.SetName(firstName: firstName, lastName: lastName));

  Future<void> setBio(String bio) => _client.invoke<td.Ok>(td.SetBio(bio: bio));

  /// Sets your public username; empty removes it.
  Future<void> setUsername(String username) => _client.invoke<td.Ok>(td.SetUsername(username: username));

  /// Whether [username] could be yours; null when it can, otherwise why not.
  Future<String?> checkUsername(int myUserId, String username) async {
    final r = await _client.invoke<td.CheckChatUsernameResult>(
      td.CheckChatUsername(chatId: myUserId, username: username),
    );
    return switch (r) {
      td.CheckChatUsernameResultOk() => null,
      td.CheckChatUsernameResultUsernameInvalid() => 'Invalid username',
      td.CheckChatUsernameResultUsernameOccupied() => 'This username is taken',
      td.CheckChatUsernameResultUsernamePurchasable() => 'This username is for sale on Fragment',
      td.CheckChatUsernameResultPublicChatsTooMany() => 'Too many public usernames',
      _ => 'Not available',
    };
  }
}
