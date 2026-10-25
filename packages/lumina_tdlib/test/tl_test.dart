import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/tl.dart';

const _sample = '''
double ? = Double;
string ? = String;

int32 = Int32;
int53 = Int53;
int64 = Int64;
bytes = Bytes;

boolFalse = Bool;
boolTrue = Bool;

vector {t:Type} # [ t ] = Vector t;


//@description An error @code Error code @message Error message
error code:int32 message:string = Error;

//@class AuthorizationState @description Represents the current authorization state
//-of the TDLib client

//@description TDLib is ready
authorizationStateReady = AuthorizationState;

//@description A bot
//@id Identifier
//@param_description Bot description; may be null
//@rows Keyboard rows; e.g. user@example.com may write
//-to the bot
botInfo id:int64 description:formattedText rows:vector<vector<keyboardButton>> = BotInfo;

---functions---

//@description Returns the current user
getMe = User;
''';

void main() {
  final schema = parseTl(_sample);

  test('skips builtin types', () {
    expect(schema.objects.map((c) => c.name), ['error', 'authorizationStateReady', 'botInfo']);
  });

  test('reads abstract classes with continued docs', () {
    expect(schema.classes.keys, ['AuthorizationState']);
    expect(
      schema.classes['AuthorizationState']!.doc,
      'Represents the current authorization state of the TDLib client',
    );
  });

  test('reads fields, nested vectors, param_description and continuations', () {
    final bot = schema.objects.last;
    expect(bot.result, 'BotInfo');
    expect(bot.doc, 'A bot');
    expect(bot.fields.map((f) => f.name), ['id', 'description', 'rows']);
    expect(bot.fields[0].type.name, 'int64');
    expect(bot.fields[0].type.isPrimitive, isTrue);
    expect(bot.fields[1].doc, 'Bot description; may be null');
    final rows = bot.fields[2].type;
    expect(rows.isVector, isTrue);
    expect(rows.element!.isVector, isTrue);
    expect(rows.element!.element!.name, 'keyboardButton');
    expect(bot.fields[2].doc, 'Keyboard rows; e.g. user@example.com may write to the bot');
  });

  test('reads functions', () {
    expect(schema.functions.single.name, 'getMe');
    expect(schema.functions.single.result, 'User');
    expect(schema.functions.single.isFunction, isTrue);
    expect(schema.objects.first.isFunction, isFalse);
  });

  test('rejects lines it does not understand', () {
    expect(() => parseTl('this is not tl'), throwsFormatException);
  });

  test('parses the pinned schema completely', () {
    final real = parseTl(File('schema/td_api.tl').readAsStringSync());
    expect(real.objects.length + real.functions.length, greaterThan(3000));
    expect(real.objects.map((c) => c.name), contains('updateNewMessage'));
    expect(real.functions.map((c) => c.name), contains('sendMessage'));
    for (final c in [...real.objects, ...real.functions]) {
      expect(c.doc, isNotEmpty, reason: '${c.name} has no description');
    }
  });
}
