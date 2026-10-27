import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/bots/data/bot_start_links.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

void main() {
  test('parses t.me and tg:// start links, and nothing else', () {
    expect(BotStartLinks.parse(Uri.parse('https://t.me/WeatherBot?start=ref42')), (
      username: 'WeatherBot',
      parameter: 'ref42',
    ));
    expect(BotStartLinks.parse(Uri.parse('tg://resolve?domain=WeatherBot&start=x')), (
      username: 'WeatherBot',
      parameter: 'x',
    ));
    expect(BotStartLinks.parse(Uri.parse('https://t.me/WeatherBot')), isNull);
    expect(BotStartLinks.parse(Uri.parse('https://t.me/c/123?start=x')), isNull);
    expect(BotStartLinks.parse(Uri.parse('https://example.org/WeatherBot?start=x')), isNull);
  });

  test('a bot link stores the parameter for its chat until taken', () async {
    final client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.SearchPublicChat() => fakeChat(9),
        td.GetUser() => fakeUser(bot: true).copyWith(id: 9),
        _ => const td.Ok(),
      };
    final links = BotStartLinks(client);
    expect(await links.resolve(Uri.parse('https://t.me/WeatherBot?start=ref42')), 9);
    expect(links.peek(9), 'ref42');
    expect(links.take(9), 'ref42');
    expect(links.take(9), isNull);
  });

  test('a start link to a non-bot stores nothing', () async {
    final client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.SearchPublicChat() => fakeChat(9),
        td.GetUser() => fakeUser().copyWith(id: 9),
        _ => const td.Ok(),
      };
    final links = BotStartLinks(client);
    expect(await links.resolve(Uri.parse('https://t.me/ada?start=x')), isNull);
    expect(links.peek(9), isNull);
  });

  test('an unknown username resolves to nothing', () async {
    final client = FakeTdClient()
      ..respond = (_) => const td.TdError(code: 400, message: 'USERNAME_NOT_OCCUPIED');
    expect(await BotStartLinks(client).resolve(Uri.parse('https://t.me/nobody?start=x')), isNull);
  });
}
