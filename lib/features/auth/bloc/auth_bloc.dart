import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../core/tdlib/td_errors.dart';
import '../data/auth_repository.dart';
import '../domain/account_capabilities.dart';
import '../domain/auth_error_outcome.dart';
import '../domain/auth_step.dart';

part 'auth_event.dart';
part 'auth_state.dart';

/// Why the app asked TDLib to close, which decides what happens at
/// `authorizationStateClosed`.
enum _CloseIntent { none, logOut, resetLocalData }

/// Drives TDLib's authorization state machine for both phone and bot-token
/// login, and owns the client's close / recreate cycle.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required AuthRepository repository, DateTime Function()? clock})
    : _repository = repository,
      _now = clock ?? DateTime.now,
      super(
        AuthState(
          step: repository.hasApiCredentials ? const AuthBooting() : const AuthMissingApiCredentials(),
        ),
      ) {
    on<AuthStarted>(_onStarted, transformer: droppable());
    // TDLib states must be applied in order, each fully (e.g. Ready -> GetMe).
    on<_AuthorizationStateChanged>(_onAuthorizationState, transformer: sequential());
    on<AuthSubmitted>(_onSubmitted, transformer: droppable());
    on<AuthPhoneChangeRequested>(
      (_, emit) => emit(state.copyWith(phoneEntryOverride: true, inlineError: () => null)),
    );
    on<AuthNoticeDismissed>((_, emit) => emit(state.copyWith(notice: () => null)));
    on<AuthLogOutRequested>(_onLogOut, transformer: droppable());
    on<AuthLocalDataResetRequested>(_onReset, transformer: droppable());
  }

  final AuthRepository _repository;
  final DateTime Function() _now;
  StreamSubscription<td.AuthorizationState>? _subscription;
  var _closeIntent = _CloseIntent.none;

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    if (!_repository.hasApiCredentials || _subscription != null) return;
    // Subscribe before starting so the first authorization update is seen.
    _subscription = _repository.authorizationStates.listen((s) => add(_AuthorizationStateChanged(s)));
    await _repository.start();
  }

  Future<void> _onAuthorizationState(_AuthorizationStateChanged event, Emitter<AuthState> emit) async {
    switch (event.state) {
      case td.AuthorizationStateWaitTdlibParameters():
        try {
          await _repository.sendTdlibParameters();
        } on TdException catch (e) {
          emit(AuthState(step: AuthDatabaseError(e.message)));
        }
      case td.AuthorizationStateWaitPhoneNumber():
        emit(_enter(const AuthWaitPhone()));
      case td.AuthorizationStateWaitCode(:final codeInfo):
        emit(_enter(AuthWaitCode(codeInfo)));
      case td.AuthorizationStateWaitEmailAddress():
        emit(_enter(const AuthWaitEmailAddress()));
      case td.AuthorizationStateWaitEmailCode(:final codeInfo):
        emit(_enter(AuthWaitEmailCode(codeInfo)));
      case td.AuthorizationStateWaitPassword(:final passwordHint, :final hasRecoveryEmailAddress):
        emit(_enter(AuthWaitPassword(hint: passwordHint, hasRecoveryEmail: hasRecoveryEmailAddress)));
      case td.AuthorizationStateWaitRegistration(:final termsOfService):
        emit(_enter(AuthWaitRegistration(termsOfService.text.text)));
      case td.AuthorizationStateWaitOtherDeviceConfirmation(:final link):
        emit(_enter(AuthWaitOtherDevice(link)));
      case td.AuthorizationStateReady():
        try {
          final me = await _repository.getMe();
          emit(AuthState(step: AuthReady(me, AccountCapabilities.forUser(me))));
        } on Exception catch (e) {
          emit(state.copyWith(inlineError: () => 'Signed in, but loading the account failed: $e'));
        }
      case td.AuthorizationStateLoggingOut() || td.AuthorizationStateClosing():
        emit(_enter(const AuthClosing()));
      case td.AuthorizationStateClosed():
        await _onClosed(emit);
    }
  }

  /// A new step clears per-screen errors and the expired-code detour but
  /// keeps any flood block and pending notice.
  AuthState _enter(AuthStep step) =>
      AuthState(step: step, floodUntil: state.floodUntil, notice: state.notice);

  Future<void> _onClosed(Emitter<AuthState> emit) async {
    final intent = _closeIntent;
    _closeIntent = _CloseIntent.none;
    // The client is closed, so its files are no longer in use.
    if (intent != _CloseIntent.none) await _repository.wipeLocalData();
    emit(
      AuthState(
        step: const AuthBooting(),
        notice: intent == _CloseIntent.none ? 'Your session ended. Sign in again.' : null,
      ),
    );
    await _repository.recreateClient();
  }

  Future<void> _onSubmitted(AuthSubmitted event, Emitter<AuthState> emit) async {
    if (state.busy || state.isFloodBlocked(_now())) return;

    // TDLib accepts bot tokens only in WaitPhoneNumber; while a code is
    // pending we are only *showing* phone entry.
    if (event is AuthBotTokenSubmitted && state.step is! AuthWaitPhone) {
      emit(
        state.copyWith(
          inlineError: () => 'A phone sign-in is in progress. Use "Start over" to sign in as a bot.',
        ),
      );
      return;
    }

    final (action, request) = switch (event) {
      AuthPhoneNumberSubmitted(:final phoneNumber) => (
        AuthAction.phone,
        () => _repository.setPhoneNumber(phoneNumber),
      ),
      AuthBotTokenSubmitted(:final token) => (AuthAction.botToken, () => _repository.checkBotToken(token)),
      AuthCodeSubmitted(:final code) => (AuthAction.code, () => _repository.checkCode(code)),
      AuthCodeResendRequested() => (AuthAction.code, _repository.resendCode),
      AuthPasswordSubmitted(:final password) => (
        AuthAction.password,
        () => _repository.checkPassword(password),
      ),
      AuthRegistrationSubmitted(:final firstName, :final lastName) => (
        AuthAction.registration,
        () => _repository.register(firstName, lastName),
      ),
      AuthEmailAddressSubmitted(:final email) => (AuthAction.email, () => _repository.setEmailAddress(email)),
      AuthEmailCodeSubmitted(:final code) => (AuthAction.emailCode, () => _repository.checkEmailCode(code)),
    };

    emit(state.copyWith(busy: true, inlineError: () => null, notice: () => null));
    try {
      await request();
      // The resulting authorization update may already have been applied;
      // only clear what this submission set.
      emit(state.copyWith(busy: false, phoneEntryOverride: event is AuthPhoneNumberSubmitted ? false : null));
    } on TdException catch (e) {
      final outcome = classifyAuthError(e, action);
      final wait = outcome.floodWait;
      emit(
        state.copyWith(
          busy: false,
          inlineError: () => outcome.inlineError,
          floodUntil: wait == null ? null : () => _now().add(wait),
          phoneEntryOverride: outcome.backToPhoneEntry ? true : null,
        ),
      );
    } on TdTransportException catch (e) {
      emit(state.copyWith(busy: false, inlineError: () => e.message));
    }
  }

  /// Full logout: server session terminated, then (at `Closed`) database,
  /// files and encryption key deleted. Nothing can auto-authenticate after.
  Future<void> _onLogOut(AuthLogOutRequested event, Emitter<AuthState> emit) async {
    _closeIntent = _CloseIntent.logOut;
    emit(const AuthState(step: AuthClosing()));
    await _repository.logOut();
  }

  Future<void> _onReset(AuthLocalDataResetRequested event, Emitter<AuthState> emit) async {
    _closeIntent = _CloseIntent.resetLocalData;
    emit(const AuthState(step: AuthClosing()));
    await _repository.destroy();
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
