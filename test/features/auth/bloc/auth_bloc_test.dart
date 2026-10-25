import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:lumina/core/config/app_config.dart';
import 'package:lumina/features/auth/bloc/auth_bloc.dart';
import 'package:lumina/features/auth/domain/auth_step.dart';

import '../../../helpers/fakes.dart';

void main() {
  late AuthHarness h;
  late DateTime now;

  AuthBloc makeBloc() {
    final bloc = AuthBloc(repository: h.repository, clock: () => now);
    addTearDown(bloc.close);
    return bloc;
  }

  /// Starts the bloc and walks TDLib to authorizationStateWaitPhoneNumber.
  Future<AuthBloc> bootToPhone() async {
    final bloc = makeBloc()..add(const AuthStarted());
    await settle();
    h.client.emit(const td.AuthorizationStateWaitTdlibParameters());
    await settle();
    h.client.emit(const td.AuthorizationStateWaitPhoneNumber());
    await settle();
    return bloc;
  }

  Future<AuthBloc> bootToCode() async {
    final bloc = await bootToPhone();
    bloc.add(const AuthPhoneNumberSubmitted('+44 (7700) 900-000'));
    await settle();
    h.client.emit(const td.AuthorizationStateWaitCode(codeInfo: smsCodeInfo));
    await settle();
    return bloc;
  }

  setUp(() {
    h = AuthHarness();
    now = DateTime(2026, 10, 25, 12);
  });

  group('boot', () {
    blocTest<AuthBloc, AuthState>(
      'missing API credentials: stays put and never starts TDLib',
      setUp: () => h = AuthHarness(settings: const TdSettings(apiId: 0, apiHash: '')),
      build: () => AuthBloc(repository: h.repository),
      act: (bloc) => bloc.add(const AuthStarted()),
      expect: () => isEmpty,
      verify: (bloc) {
        expect(bloc.state.step, isA<AuthMissingApiCredentials>());
        expect(h.client.starts, 0);
      },
    );

    test('sends absolute directories and the stored key, then shows phone entry', () async {
      final bloc = await bootToPhone();
      expect(h.client.starts, 1);
      final params = h.client.sentOf<td.SetTdlibParameters>().single;
      expect(params.databaseDirectory, startsWith('/'));
      expect(params.filesDirectory, startsWith('/'));
      expect(params.databaseEncryptionKey, 'a2V5');
      expect(params.apiId, 1);
      expect(bloc.state.step, isA<AuthWaitPhone>());
    });

    test('rejected parameters show the database error; reset destroys and wipes', () async {
      h.client.respond = (f) => f is td.SetTdlibParameters
          ? const td.TdError(code: 401, message: 'Wrong database encryption key')
          : const td.Ok();
      final bloc = makeBloc()..add(const AuthStarted());
      await settle();
      h.client.emit(const td.AuthorizationStateWaitTdlibParameters());
      await settle();
      expect(bloc.state.step, isA<AuthDatabaseError>());

      bloc.add(const AuthLocalDataResetRequested());
      await settle();
      expect(h.client.sentOf<td.Destroy>(), hasLength(1));
      h.client.emit(const td.AuthorizationStateClosed());
      await settle();
      expect(h.paths.wipes, 1);
      expect(h.secure.discards, 1);
      expect(h.client.recreations, 1);
    });
  });

  group('bot login', () {
    test('token is checked in WaitPhoneNumber and capabilities are gated', () async {
      h.client.respond = (f) => f is td.GetMe ? fakeUser(bot: true) : const td.Ok();
      final bloc = await bootToPhone();

      bloc.add(const AuthBotTokenSubmitted('  123:abc  '));
      await settle();
      expect(h.client.sentOf<td.CheckAuthenticationBotToken>().single.token, '123:abc');

      h.client.emit(const td.AuthorizationStateReady());
      await settle();
      final caps = (bloc.state.step as AuthReady).capabilities;
      expect(caps.isBot, isTrue);
      expect(caps.secretChats, isFalse);
      expect(caps.onlinePresence, isFalse);
      expect(caps.startPrivateChats, isFalse);
      expect(caps.fullGroupManagement, isFalse);
      expect(caps.limitations, isNotEmpty);
    });

    test('token is refused locally while TDLib waits for a code', () async {
      final bloc = await bootToCode();
      bloc.add(const AuthPhoneChangeRequested());
      await settle();

      bloc.add(const AuthBotTokenSubmitted('123:abc'));
      await settle();
      expect(h.client.sentOf<td.CheckAuthenticationBotToken>(), isEmpty);
      expect(bloc.state.inlineError, contains('Start over'));
    });

    test('a regular user keeps every capability', () async {
      h.client.respond = (f) => f is td.GetMe ? fakeUser() : const td.Ok();
      final bloc = await bootToPhone();
      h.client.emit(const td.AuthorizationStateReady());
      await settle();
      final caps = (bloc.state.step as AuthReady).capabilities;
      expect(caps.isBot, isFalse);
      expect(caps.limitations, isEmpty);
    });
  });

  group('phone login (spec §4.2 error table)', () {
    test('phone number is normalized before sending', () async {
      await bootToCode();
      expect(h.client.sentOf<td.SetAuthenticationPhoneNumber>().single.phoneNumber, '+447700900000');
    });

    test('PHONE_NUMBER_INVALID: inline error, stays on phone entry', () async {
      h.client.respond = (_) => const td.TdError(code: 400, message: 'PHONE_NUMBER_INVALID');
      final bloc = await bootToPhone();
      bloc.add(const AuthPhoneNumberSubmitted('+1'));
      await settle();
      expect(bloc.state.visibleStep, isA<AuthWaitPhone>());
      expect(bloc.state.inlineError, isNotNull);
      expect(bloc.state.busy, isFalse);
    });

    test('PHONE_CODE_INVALID: inline error, stays on code screen', () async {
      final bloc = await bootToCode();
      h.client.respond = (_) => const td.TdError(code: 400, message: 'PHONE_CODE_INVALID');
      bloc.add(const AuthCodeSubmitted('11111'));
      await settle();
      expect(bloc.state.visibleStep, isA<AuthWaitCode>());
      expect(bloc.state.inlineError, isNotNull);
    });

    test('PHONE_CODE_EXPIRED: back to phone entry; a new code ends the detour', () async {
      final bloc = await bootToCode();
      h.client.respond = (_) => const td.TdError(code: 400, message: 'PHONE_CODE_EXPIRED');
      bloc.add(const AuthCodeSubmitted('11111'));
      await settle();
      expect(bloc.state.step, isA<AuthWaitCode>());
      expect(bloc.state.visibleStep, isA<AuthWaitPhone>());
      expect(bloc.state.inlineError, contains('expired'));

      h.client.respond = (_) => const td.Ok();
      bloc.add(const AuthPhoneNumberSubmitted('+447700900000'));
      await settle();
      h.client.emit(const td.AuthorizationStateWaitCode(codeInfo: smsCodeInfo));
      await settle();
      expect(bloc.state.visibleStep, isA<AuthWaitCode>());
      expect(bloc.state.inlineError, isNull);
    });

    test('PASSWORD_HASH_INVALID: inline error, stays on password screen', () async {
      final bloc = await bootToCode();
      h.client.emit(
        const td.AuthorizationStateWaitPassword(
          passwordHint: 'pet',
          hasRecoveryEmailAddress: false,
          hasPassportData: false,
          recoveryEmailAddressPattern: '',
        ),
      );
      await settle();
      h.client.respond = (_) => const td.TdError(code: 400, message: 'PASSWORD_HASH_INVALID');
      bloc.add(const AuthPasswordSubmitted('nope'));
      await settle();
      expect(bloc.state.visibleStep, isA<AuthWaitPassword>());
      expect(bloc.state.inlineError, 'Incorrect password.');
    });

    test('back from the password screen shows phone entry (UX-14)', () async {
      final bloc = await bootToCode();
      h.client.emit(
        const td.AuthorizationStateWaitPassword(
          passwordHint: '',
          hasRecoveryEmailAddress: false,
          hasPassportData: false,
          recoveryEmailAddressPattern: '',
        ),
      );
      await settle();
      bloc.add(const AuthPhoneChangeRequested());
      await settle();
      expect(bloc.state.visibleStep, isA<AuthWaitPhone>());
    });

    test('FLOOD_WAIT: submissions blocked until the wait passes', () async {
      h.client.respond = (_) => const td.TdError(code: 429, message: 'Too Many Requests: retry after 30');
      final bloc = await bootToPhone();
      bloc.add(const AuthPhoneNumberSubmitted('+447700900000'));
      await settle();
      expect(bloc.state.floodUntil, now.add(const Duration(seconds: 30)));

      final before = h.client.sent.length;
      bloc.add(const AuthPhoneNumberSubmitted('+447700900000'));
      await settle();
      expect(h.client.sent.length, before, reason: 'blocked while flood-waiting');

      now = now.add(const Duration(seconds: 31));
      h.client.respond = (_) => const td.Ok();
      bloc.add(const AuthPhoneNumberSubmitted('+447700900000'));
      await settle();
      expect(h.client.sent.length, before + 1);
    });

    test('a second tap while the first request is in flight is dropped', () async {
      final bloc = await bootToPhone();
      final answer = Completer<td.TdObject>();
      h.client.respond = (_) => answer.future;
      bloc
        ..add(const AuthPhoneNumberSubmitted('+447700900000'))
        ..add(const AuthPhoneNumberSubmitted('+447700900000'));
      await settle();
      expect(h.client.sentOf<td.SetAuthenticationPhoneNumber>(), hasLength(1));
      expect(bloc.state.busy, isTrue);
      answer.complete(const td.Ok());
      await settle();
      expect(bloc.state.busy, isFalse);
    });
  });

  group('session', () {
    test('logOut wipes local data and recreates the client at Closed', () async {
      h.client.respond = (f) => f is td.GetMe ? fakeUser() : const td.Ok();
      final bloc = await bootToPhone();
      h.client.emit(const td.AuthorizationStateReady());
      await settle();

      bloc.add(const AuthLogOutRequested());
      await settle();
      expect(h.client.sentOf<td.LogOut>(), hasLength(1));
      expect(bloc.state.step, isA<AuthClosing>());

      h.client
        ..emit(const td.AuthorizationStateLoggingOut())
        ..emit(const td.AuthorizationStateClosed());
      await settle();
      expect(h.paths.wipes, 1);
      expect(h.secure.discards, 1);
      expect(h.client.recreations, 1);
      expect(bloc.state.notice, isNull);
    });

    test('logOut falls back to Close when the server is unreachable', () async {
      final bloc = await bootToPhone();
      h.client.respond = (f) =>
          f is td.LogOut ? const td.TdError(code: 500, message: 'network') : const td.Ok();
      bloc.add(const AuthLogOutRequested());
      await settle();
      expect(h.client.sentOf<td.Close>(), hasLength(1));
    });

    test('an unexpected close keeps data and tells the user why', () async {
      final bloc = await bootToPhone();
      h.client.emit(const td.AuthorizationStateClosed());
      await settle();
      expect(h.paths.wipes, 0);
      expect(h.client.recreations, 1);
      expect(bloc.state.notice, contains('session ended'));
    });
  });
}
