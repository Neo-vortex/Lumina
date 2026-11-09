import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_tdlib/api.dart' as td;

void main() {
  // A self-hosted server's auth.authorizationSignUpRequired has no terms of
  // service; TDLib then sends terms_of_service: null. Dropping that update
  // left the app on "Waking up…" forever.
  test('waitRegistration without terms of service parses', () {
    final s = td.AuthorizationStateWaitRegistration.fromJson({
      '@type': 'authorizationStateWaitRegistration',
      'terms_of_service': null,
    });
    expect(s.termsOfService, isNull);
  });

  test('waitRegistration with terms still parses them', () {
    final s = td.AuthorizationStateWaitRegistration.fromJson({
      '@type': 'authorizationStateWaitRegistration',
      'terms_of_service': {
        '@type': 'termsOfService',
        'text': {'@type': 'formattedText', 'text': 'Be nice', 'entities': <Object>[]},
        'min_user_age': 0,
        'show_popup': false,
      },
    });
    expect(s.termsOfService?.text.text, 'Be nice');
  });
}
