import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/tdlib/td_client.dart';
import '../../../core/tdlib/td_errors.dart';

/// TDLib requests for chatting with bots: their profile info (cached) and
/// /start.
class BotsRepository {
  BotsRepository(this._client);

  final TdClient _client;
  final _info = <int, td.BotInfo>{};

  /// The bot's description, photo, commands, menu button…; null when the
  /// user is not a bot or the lookup failed (retried next call).
  Future<td.BotInfo?> info(int botUserId) async {
    if (_info[botUserId] case final cached?) return cached;
    try {
      final full = await _client.invoke<td.UserFullInfo>(td.GetUserFullInfo(userId: botUserId));
      final bot = full.botInfo;
      if (bot != null) _info[botUserId] = bot;
      return bot;
    } on TdException {
      return null;
    }
  }

  /// "Start": `/start` with an optional deep-link [parameter].
  Future<void> start({required int botUserId, required int chatId, String parameter = ''}) => _client
      .invoke<td.Message>(td.SendBotStartMessage(botUserId: botUserId, chatId: chatId, parameter: parameter));
}
