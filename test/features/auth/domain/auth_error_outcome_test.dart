import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/auth/domain/auth_error_outcome.dart';
import 'package:lumina/core/tdlib/td_errors.dart';

void main() {
  AuthErrorOutcome classify(String message, [AuthAction action = AuthAction.code, int code = 400]) =>
      classifyAuthError(TdException(code, message), action);

  test('flood wait in both TDLib spellings', () {
    expect(const TdException(420, 'FLOOD_WAIT_37').floodWaitSeconds, 37);
    expect(const TdException(429, 'Too Many Requests: retry after 120').floodWaitSeconds, 120);
    expect(const TdException(400, 'PHONE_CODE_INVALID').floodWaitSeconds, isNull);

    final outcome = classify('Too Many Requests: retry after 90', AuthAction.phone, 429);
    expect(outcome.floodWait, const Duration(seconds: 90));
    expect(outcome.inlineError, contains('2 min'));
  });

  test('PHONE_NUMBER_INVALID is an inline error', () {
    final o = classify('PHONE_NUMBER_INVALID', AuthAction.phone);
    expect(o.inlineError, isNotNull);
    expect(o.backToPhoneEntry, isFalse);
  });

  test('PHONE_CODE_INVALID keeps the code screen', () {
    final o = classify('PHONE_CODE_INVALID');
    expect(o.inlineError, isNotNull);
    expect(o.backToPhoneEntry, isFalse);
  });

  test('PHONE_CODE_EXPIRED returns to phone entry', () {
    expect(classify('PHONE_CODE_EXPIRED').backToPhoneEntry, isTrue);
  });

  test('PASSWORD_HASH_INVALID is an inline error', () {
    expect(classify('PASSWORD_HASH_INVALID', AuthAction.password).inlineError, 'Incorrect password.');
  });

  test('unknown errors surface the TDLib message', () {
    expect(classify('SOMETHING_ODD').inlineError, 'SOMETHING_ODD');
  });
}
