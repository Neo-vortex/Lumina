import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/bots/data/bots_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

td.UserFullInfo fullWithBot(td.BotInfo? bot) => fakeUserFullInfo(botInfo: bot);

const bot = td.BotInfo(
  shortDescription: 'Weather in a tap',
  description: 'I tell you the weather.',
  managerBotUserId: 0,
  commands: [td.BotCommand(command: 'today', description: 'Weather today', isEphemeral: false)],
  privacyPolicyUrl: 'https://example.org/p',
  webAppBackgroundLightColor: -1,
  webAppBackgroundDarkColor: -1,
  webAppHeaderLightColor: -1,
  webAppHeaderDarkColor: -1,
  canGetRevenueStatistics: false,
  canManageEmojiStatus: false,
  hasMediaPreviews: false,
);

void main() {
  test('bot info is fetched once and cached', () async {
    final client = FakeTdClient()
      ..respond = (f) => f is td.GetUserFullInfo ? fullWithBot(bot) : const td.Ok();
    final repo = BotsRepository(client);
    expect((await repo.info(9))!.description, 'I tell you the weather.');
    await repo.info(9);
    expect(client.sentOf<td.GetUserFullInfo>(), hasLength(1));
  });

  test('a failed lookup returns null and is retried next time', () async {
    var fail = true;
    final client = FakeTdClient()
      ..respond = (f) => fail ? const td.TdError(code: 500, message: 'boom') : fullWithBot(bot);
    final repo = BotsRepository(client);
    expect(await repo.info(9), isNull);
    fail = false;
    expect(await repo.info(9), isNotNull);
  });

  test('start sends sendBotStartMessage with the parameter', () async {
    final client = FakeTdClient()..respond = (_) => fakeMessage(1);
    await BotsRepository(client).start(botUserId: 9, chatId: 9, parameter: 'ref42');
    final s = client.sentOf<td.SendBotStartMessage>().single;
    expect((s.botUserId, s.chatId, s.parameter), (9, 9, 'ref42'));
  });
}
