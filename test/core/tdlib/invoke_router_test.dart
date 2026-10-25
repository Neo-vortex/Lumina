import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib_next/api.dart' as td;
import 'package:lumina/core/tdlib/invoke_router.dart';
import 'package:lumina/core/tdlib/td_errors.dart';
import 'package:lumina/core/tdlib/isolates/td_messages.dart';

void main() {
  late InvokeRouter router;
  setUp(() => router = InvokeRouter());

  test('routes a result to the caller with the matching extra', () async {
    final (a, futureA) = router.register();
    final (b, futureB) = router.register();
    expect(a, isNot(b));

    expect(router.deliver(td.Ok(extra: b)), isTrue);
    expect(router.deliver(td.Ok(extra: a)), isTrue);

    expect(await futureA, isA<td.Ok>());
    expect(await futureB, isA<td.Ok>());
    expect(router.pendingCount, 0);
  });

  test('objects without extra are updates and are not consumed', () {
    router.register();
    expect(
      router.deliver(const td.UpdateAuthorizationState(authorizationState: td.AuthorizationStateReady())),
      isFalse,
    );
    expect(router.pendingCount, 1);
  });

  test('an unknown extra is not consumed', () {
    expect(router.deliver(const td.Ok(extra: 999)), isFalse);
  });

  test('TDLib errors fail the caller with TdException', () async {
    final (extra, future) = router.register();
    router.deliver(td.TdError(code: 400, message: 'PHONE_NUMBER_INVALID', extra: extra));
    await expectLater(
      future,
      throwsA(isA<TdException>().having((e) => e.message, 'message', 'PHONE_NUMBER_INVALID')),
    );
  });

  test('a parse failure fails the caller instead of hanging it', () async {
    final (extra, future) = router.register();
    router.deliverFailure(ParseFailure(type: 'somethingNew', error: 'unknown', extra: extra));
    await expectLater(future, throwsA(isA<TdTransportException>()));
  });

  test('failAll fails every pending invoke', () async {
    final (_, a) = router.register();
    final (_, b) = router.register();
    router.failAll('closed');
    await expectLater(a, throwsA(isA<TdTransportException>()));
    await expectLater(b, throwsA(isA<TdTransportException>()));
  });

  test('timeouts fail the caller and a late answer is ignored', () async {
    final (extra, future) = router.register(timeout: const Duration(milliseconds: 10));
    await expectLater(future, throwsA(isA<TdTransportException>()));
    expect(router.deliver(td.Ok(extra: extra)), isFalse);
  });
}
