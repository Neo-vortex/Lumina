import '../../../core/tdlib/td_errors.dart';

/// One line for a failed folder action. Limit errors name the limit.
String folderErrorText(Object error) {
  if (error is! TdException) return '$error';
  return switch (error.message) {
    'CHATLISTS_TOO_MUCH' ||
    'DIALOG_FILTERS_TOO_MUCH' ||
    'FILTERS_TOO_MUCH' => 'You have reached the folder limit (10 without Telegram Premium)',
    'FILTER_INCLUDE_TOO_MUCH' ||
    'CHATLIST_INCLUDE_TOO_MUCH' => 'This folder has too many chats (100 without Telegram Premium)',
    'FILTER_EXCLUDE_TOO_MUCH' => 'This folder excludes too many chats',
    'FILTER_TITLE_EMPTY' => 'Give the folder a name',
    'FILTER_ID_INVALID' || 'CHAT_FOLDER_NOT_FOUND' => 'This folder was deleted',
    'INVITE_SLUG_EXPIRED' => 'This folder link has expired',
    'INVITE_SLUG_EMPTY' || 'INVITE_SLUG_INVALID' => 'This folder link is not valid',
    'CHATLISTS_INVITES_TOO_MUCH' || 'INVITES_TOO_MUCH' => 'This folder has too many invite links',
    'USER_CHANNELS_TOO_MUCH' || 'CHANNELS_TOO_MUCH' => 'You are in too many groups and channels to join more',
    'PREMIUM_ACCOUNT_REQUIRED' => 'This needs Telegram Premium',
    final m => m,
  };
}
