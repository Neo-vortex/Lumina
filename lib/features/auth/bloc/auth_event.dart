part of 'auth_bloc.dart';

sealed class AuthEvent {
  const AuthEvent();
}

/// Starts TDLib and begins following its authorization state.
final class AuthStarted extends AuthEvent {
  const AuthStarted();
}

/// Internal: TDLib reported a new `authorizationState`.
final class _AuthorizationStateChanged extends AuthEvent {
  const _AuthorizationStateChanged(this.state);
  final td.AuthorizationState state;
}

/// A form submission. Handled one at a time; repeats while busy are dropped.
sealed class AuthSubmitted extends AuthEvent {
  const AuthSubmitted();
}

final class AuthPhoneNumberSubmitted extends AuthSubmitted {
  const AuthPhoneNumberSubmitted(this.phoneNumber);
  final String phoneNumber;
}

final class AuthBotTokenSubmitted extends AuthSubmitted {
  const AuthBotTokenSubmitted(this.token);
  final String token;
}

final class AuthCodeSubmitted extends AuthSubmitted {
  const AuthCodeSubmitted(this.code);
  final String code;
}

final class AuthCodeResendRequested extends AuthSubmitted {
  const AuthCodeResendRequested();
}

final class AuthPasswordSubmitted extends AuthSubmitted {
  const AuthPasswordSubmitted(this.password);
  final String password;
}

final class AuthRegistrationSubmitted extends AuthSubmitted {
  const AuthRegistrationSubmitted({required this.firstName, required this.lastName});
  final String firstName;
  final String lastName;
}

final class AuthEmailAddressSubmitted extends AuthSubmitted {
  const AuthEmailAddressSubmitted(this.email);
  final String email;
}

final class AuthEmailCodeSubmitted extends AuthSubmitted {
  const AuthEmailCodeSubmitted(this.code);
  final String code;
}

/// Show phone entry again while TDLib still waits for a code.
final class AuthPhoneChangeRequested extends AuthEvent {
  const AuthPhoneChangeRequested();
}

final class AuthNoticeDismissed extends AuthEvent {
  const AuthNoticeDismissed();
}

/// Full logout. Also used to abandon a pending login ("Start over"), since
/// TDLib has no cancel short of closing the client.
final class AuthLogOutRequested extends AuthEvent {
  const AuthLogOutRequested();
}

/// Destroy local data without a server logout (corrupt DB / lost key).
final class AuthLocalDataResetRequested extends AuthEvent {
  const AuthLocalDataResetRequested();
}
