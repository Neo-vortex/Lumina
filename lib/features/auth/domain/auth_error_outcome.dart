import '../../../core/tdlib/td_errors.dart';

/// Which auth submission failed; the same server error can mean different
/// things on different screens.
enum AuthAction { phone, botToken, code, password, registration, email, emailCode }

/// What the UI must do about a failed auth submission.
class AuthErrorOutcome {
  const AuthErrorOutcome({this.inlineError, this.floodWait, this.backToPhoneEntry = false});

  final String? inlineError;
  final Duration? floodWait;
  final bool backToPhoneEntry;
}

/// Maps TDLib auth errors to the behaviour required by the spec (§4.2).
AuthErrorOutcome classifyAuthError(TdException e, AuthAction action) {
  final flood = e.floodWaitSeconds;
  if (flood != null) {
    return AuthErrorOutcome(
      floodWait: Duration(seconds: flood),
      inlineError: 'Too many attempts. Try again in ${_humanize(flood)}.',
    );
  }
  if (e.hasServerError('PHONE_NUMBER_INVALID')) {
    return const AuthErrorOutcome(
      inlineError: 'That number is not valid. Include the country code, e.g. +44…',
    );
  }
  if (e.hasServerError('PHONE_NUMBER_BANNED')) {
    return const AuthErrorOutcome(inlineError: 'This phone number is banned from Telegram.');
  }
  if (e.hasServerError('PHONE_CODE_EXPIRED')) {
    return const AuthErrorOutcome(
      backToPhoneEntry: true,
      inlineError: 'That code expired. Enter your number to get a new one.',
    );
  }
  if (e.hasServerError('PHONE_CODE_INVALID') || e.hasServerError('PHONE_CODE_EMPTY')) {
    return const AuthErrorOutcome(inlineError: 'Wrong code. Check it and try again.');
  }
  if (e.hasServerError('PASSWORD_HASH_INVALID')) {
    return const AuthErrorOutcome(inlineError: 'Incorrect password.');
  }
  if (e.hasServerError('ACCESS_TOKEN_INVALID') || e.hasServerError('ACCESS_TOKEN_EXPIRED')) {
    return const AuthErrorOutcome(inlineError: 'Bot token rejected. Copy it again from @BotFather.');
  }
  if (e.hasServerError('EMAIL_CODE_INVALID') || e.hasServerError('CODE_INVALID')) {
    return const AuthErrorOutcome(inlineError: 'Wrong code. Check it and try again.');
  }
  if (e.hasServerError('EMAIL_INVALID')) {
    return const AuthErrorOutcome(inlineError: 'That email address is not valid.');
  }
  if (e.hasServerError('FIRSTNAME_INVALID')) {
    return const AuthErrorOutcome(inlineError: 'Enter a first name.');
  }
  return AuthErrorOutcome(inlineError: e.message);
}

String _humanize(int seconds) {
  if (seconds < 60) return '$seconds s';
  if (seconds < 3600) return '${(seconds / 60).ceil()} min';
  return '${(seconds / 3600).toStringAsFixed(1)} h';
}
