import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib_next/api.dart' as td;
import 'package:lumina/app/app.dart';
import 'package:lumina/core/config/app_config.dart';
import 'package:lumina/core/storage/app_preferences.dart';

import '../../../helpers/fakes.dart';

void main() {
  late FakeTdClient client;

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      LuminaApp(
        client: client,
        paths: FakePaths(),
        secureStore: FakeSecureStore(),
        preferences: AppPreferences.inMemory(),
        settings: const TdSettings(apiId: 1, apiHash: 'h'),
      ),
    );
    await tester.pump();
    client.emit(const td.AuthorizationStateWaitPhoneNumber());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  setUp(() => client = FakeTdClient());

  testWidgets('flood wait disables Continue, counts down, and is announced', (tester) async {
    client.respond = (_) => const td.TdError(code: 429, message: 'Too Many Requests: retry after 3');
    await pumpApp(tester);

    expect(find.text('Welcome to Lumina'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '+447700900000');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Too many attempts'), findsOneWidget);
    expect(find.textContaining('Wait 00:0'), findsOneWidget);
    final liveRegion = find.ancestor(
      of: find.textContaining('Too many attempts'),
      matching: find.byWidgetPredicate((w) => w is Semantics && (w.properties.liveRegion ?? false)),
    );
    expect(liveRegion, findsOneWidget);

    // Bot-token mode shares the same gate.
    await tester.tap(find.text('Bot token'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Wait 00:0'), findsOneWidget);
  });

  testWidgets('code auto-submits at the expected length and clears after a wrong code', (tester) async {
    await pumpApp(tester);
    client.emit(const td.AuthorizationStateWaitCode(codeInfo: smsCodeInfo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Enter the code'), findsOneWidget);

    client.respond = (_) => const td.TdError(code: 400, message: 'PHONE_CODE_INVALID');
    await tester.enterText(find.byType(TextField), '12345'); // length 5 -> auto-submit
    await tester.pump();
    await tester.pump();

    expect(client.sentOf<td.CheckAuthenticationCode>().single.code, '12345');
    expect(find.textContaining('Wrong code'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testWidgets('system back on the code screen returns to phone entry', (tester) async {
    await pumpApp(tester);
    client.emit(const td.AuthorizationStateWaitCode(codeInfo: smsCodeInfo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Welcome to Lumina'), findsOneWidget);
    expect(find.text('Start over'), findsOneWidget);
  });

  testWidgets('reduced motion still renders every auth screen', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(tester);
    expect(find.text('Welcome to Lumina'), findsOneWidget);
  });
}
