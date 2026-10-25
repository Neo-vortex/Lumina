import 'dart:io' as io;

import 'package:lumina_tdlib/api.dart';
import 'package:test/test.dart';

void main() {
  test('version constants match schema/VERSION', () {
    final pin = io.File('schema/VERSION').readAsStringSync();
    expect(pin, contains('version=$tdlibVersion\n'));
    expect(pin, contains('commit=$tdlibCommit'));
  });

  test('int64 strings round-trip exactly', () {
    final pos = convertMapToObject({
      '@type': 'chatPosition',
      'list': {'@type': 'chatListMain'},
      'order': '9223372036854775807',
      'is_pinned': true,
    }) as ChatPosition;
    expect(pos.order, 9223372036854775807);
    expect(pos.list, isA<ChatListMain>());
    expect(pos.source, isNull);
    expect(pos.toJson()['order'], '9223372036854775807');
  });

  test('Messages keeps null entries in place', () {
    final m = convertMapToObject({
      '@type': 'messages',
      'total_count': 2,
      'messages': [null, null],
    }) as Messages;
    expect(m.messages, [null, null]);
  });

  test('nested vectors and abstract children', () {
    final markup = convertMapToObject({
      '@type': 'replyMarkupShowKeyboard',
      'rows': [
        [
          {
            '@type': 'keyboardButton',
            'text': 'Hi',
            'icon_custom_emoji_id': '0',
            'style': {'@type': 'buttonStyleDefault'},
            'type': {'@type': 'keyboardButtonTypeText'},
          },
        ],
      ],
      'is_persistent': false,
      'resize_keyboard': true,
      'one_time': false,
      'is_personal': false,
      'force_reply': false,
      'input_field_placeholder': '',
    }) as ReplyMarkupShowKeyboard;
    expect(markup.rows.single.single.text, 'Hi');
    expect(markup.rows.single.single.type, isA<KeyboardButtonTypeText>());
  });

  test('extra and client id are carried on results', () {
    final ok = convertJsonToObject('{"@type":"ok","@extra":7,"@client_id":1}') as Ok;
    expect(ok.extra, 7);
    expect(ok.clientId, 1);
    final err = convertMapToObject({'@type': 'error', 'code': 400, 'message': 'BAD'}) as TdError;
    expect(err.code, 400);
  });

  test('functions encode @type, fields and @extra', () {
    final json = const SetLogVerbosityLevel(newVerbosityLevel: 1).toJson(42);
    expect(json, {'@type': 'setLogVerbosityLevel', 'new_verbosity_level': 1, '@extra': 42});
    expect(const GetMessages(chatId: 5, messageIds: [1, 2]).toJson()['message_ids'], [1, 2]);
  });

  test('unknown types', () {
    expect(convertMapToObject({'@type': 'somethingFromTdlib2030'}), isNull);
    expect(
      () => convertMapToObject({
        '@type': 'updateAuthorizationState',
        'authorization_state': {'@type': 'authorizationStateFromTheFuture'},
      }),
      throwsFormatException,
    );
  });
}
