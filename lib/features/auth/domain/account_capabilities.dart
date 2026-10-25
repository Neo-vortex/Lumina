import 'package:handy_tdlib_next/api.dart' as td;

/// What the signed-in account may do. Bots get a reduced surface; features
/// consult this instead of checking the account type themselves.
class AccountCapabilities {
  const AccountCapabilities._({
    required this.isBot,
    required this.secretChats,
    required this.onlinePresence,
    required this.startPrivateChats,
    required this.fullGroupManagement,
    required this.browseChatList,
  });

  factory AccountCapabilities.forUser(td.User me) {
    final isBot = me.type is td.UserTypeBot;
    return AccountCapabilities._(
      isBot: isBot,
      secretChats: !isBot,
      onlinePresence: !isBot,
      startPrivateChats: !isBot,
      fullGroupManagement: !isBot,
      // Bots have no dialog list on the server; their chats become known
      // only through incoming updates. Verify against loadChats at runtime.
      browseChatList: !isBot,
    );
  }

  final bool isBot;
  final bool secretChats;
  final bool onlinePresence;
  final bool startPrivateChats;
  final bool fullGroupManagement;
  final bool browseChatList;

  /// Human-readable limitations, shown right after a bot logs in.
  List<String> get limitations => [
    if (!secretChats) 'Secret chats are unavailable to bots.',
    if (!onlinePresence) 'Bots have no online status or last-seen time.',
    if (!startPrivateChats) 'A bot cannot message a user first; the user has to start the chat.',
    if (!fullGroupManagement) 'Group management works only where the bot is an admin.',
    if (!browseChatList) 'Chats appear as messages arrive; there is no full chat history list.',
  ];
}
