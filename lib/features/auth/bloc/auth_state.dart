part of 'auth_bloc.dart';

class AuthState {
  const AuthState({
    required this.step,
    this.busy = false,
    this.inlineError,
    this.floodUntil,
    this.phoneEntryOverride = false,
    this.notice,
  });

  final AuthStep step;

  /// A request is in flight; inputs stay but submission is disabled.
  final bool busy;

  /// Error for the field on the current screen.
  final String? inlineError;

  /// Submission is blocked until this time (FLOOD_WAIT).
  final DateTime? floodUntil;

  /// Show phone entry although TDLib is further along (code, password,
  /// email, registration). Set after PHONE_CODE_EXPIRED, "Wrong number?" or
  /// back; TDLib accepts a new phone number in all of those states.
  final bool phoneEntryOverride;

  /// One-off informational message (e.g. why the user was sent back).
  final String? notice;

  /// The screen to render.
  AuthStep get visibleStep => phoneEntryOverride && step.acceptsNewPhoneNumber ? const AuthWaitPhone() : step;

  bool isFloodBlocked(DateTime now) => floodUntil != null && now.isBefore(floodUntil!);

  AuthState copyWith({
    AuthStep? step,
    bool? busy,
    String? Function()? inlineError,
    DateTime? Function()? floodUntil,
    bool? phoneEntryOverride,
    String? Function()? notice,
  }) => AuthState(
    step: step ?? this.step,
    busy: busy ?? this.busy,
    inlineError: inlineError != null ? inlineError() : this.inlineError,
    floodUntil: floodUntil != null ? floodUntil() : this.floodUntil,
    phoneEntryOverride: phoneEntryOverride ?? this.phoneEntryOverride,
    notice: notice != null ? notice() : this.notice,
  );
}
