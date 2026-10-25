import 'package:lumina_tdlib/api.dart' as td;

import 'account_capabilities.dart';

/// Where the auth flow is, derived from TDLib's `authorizationState` plus a
/// few app-level states. One step maps to one screen.
sealed class AuthStep {
  const AuthStep();

  /// TDLib's `setAuthenticationPhoneNumber` also works in these states, so
  /// the user can go back to phone entry without restarting the client.
  bool get acceptsNewPhoneNumber => switch (this) {
    AuthWaitCode() || AuthWaitPassword() || AuthWaitEmailAddress() => true,
    AuthWaitEmailCode() || AuthWaitRegistration() => true,
    _ => false,
  };
}

final class AuthBooting extends AuthStep {
  const AuthBooting();
}

/// `TG_API_ID` / `TG_API_HASH` were not provided at build time.
final class AuthMissingApiCredentials extends AuthStep {
  const AuthMissingApiCredentials();
}

/// TDLib refused its parameters, typically an unreadable or corrupt database.
final class AuthDatabaseError extends AuthStep {
  const AuthDatabaseError(this.message);
  final String message;
}

final class AuthWaitPhone extends AuthStep {
  const AuthWaitPhone();
}

final class AuthWaitCode extends AuthStep {
  const AuthWaitCode(this.info);
  final td.AuthenticationCodeInfo info;
}

final class AuthWaitEmailAddress extends AuthStep {
  const AuthWaitEmailAddress();
}

final class AuthWaitEmailCode extends AuthStep {
  const AuthWaitEmailCode(this.info);
  final td.EmailAddressAuthenticationCodeInfo info;
}

final class AuthWaitPassword extends AuthStep {
  const AuthWaitPassword({required this.hint, required this.hasRecoveryEmail});
  final String hint;
  final bool hasRecoveryEmail;
}

final class AuthWaitRegistration extends AuthStep {
  const AuthWaitRegistration(this.termsOfService);
  final String termsOfService;
}

/// Another logged-in device must confirm (QR login).
final class AuthWaitOtherDevice extends AuthStep {
  const AuthWaitOtherDevice(this.link);
  final String link;
}

final class AuthReady extends AuthStep {
  const AuthReady(this.me, this.capabilities);
  final td.User me;
  final AccountCapabilities capabilities;
}

/// Logging out, closing, or restarting the client after it closed.
final class AuthClosing extends AuthStep {
  const AuthClosing();
}
