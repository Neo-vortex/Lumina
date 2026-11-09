import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/tdlib/td_errors.dart';
import 'package:lumina/core/tdlib/unsupported_api.dart';

void main() {
  test('recognises the server\'s not-implemented errors', () {
    expect(UnsupportedApi.matches(const TdException(400, 'METHOD_NOT_IMPLEMENTED')), isTrue);
    expect(UnsupportedApi.matches(const TdException(400, 'INPUT_CONSTRUCTOR_INVALID')), isTrue);
    expect(UnsupportedApi.matches(const TdException(400, 'PHONE_CODE_INVALID')), isFalse);
  });

  test('request types read as words', () {
    expect(UnsupportedApi.readable('getChatAdministrators'), 'Get chat administrators');
    expect(UnsupportedApi.readable('searchPublicChat'), 'Search public chat');
  });
}
