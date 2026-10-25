import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/flood_gate.dart';
import '../../../../core/widgets/glow_field.dart';
import '../../bloc/auth_bloc.dart';
import '../../domain/auth_step.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/auth_submit_button.dart';
import '../widgets/back_to_phone_scope.dart';

/// Code entry: one field (paste/autofill friendly), auto-submits at the
/// expected length, clears and refocuses after a wrong code (UX-15..18).
class CodeScreen extends StatefulWidget {
  const CodeScreen({super.key, required this.step});

  final AuthWaitCode step;

  @override
  State<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends State<CodeScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  late DateTime _resendAt = _resendTime();

  DateTime _resendTime() => DateTime.now().add(Duration(seconds: widget.step.info.timeout));

  @override
  void didUpdateWidget(CodeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.step.info, widget.step.info)) {
      _resendAt = _resendTime();
      _code.clear();
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_code.text.trim().isEmpty) return;
    context.read<AuthBloc>().add(AuthCodeSubmitted(_code.text));
  }

  @override
  Widget build(BuildContext context) {
    final error = context.select((AuthBloc b) => b.state.inlineError);
    final busy = context.select((AuthBloc b) => b.state.busy);
    final info = widget.step.info;
    final kind = _describe(info.type, info.phoneNumber);

    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, next) => next.inlineError != null && prev.inlineError != next.inlineError,
      listener: (context, state) {
        _code.clear();
        _focus.requestFocus();
      },
      child: BackToPhoneScope(
        child: AuthScaffold(
          title: 'Enter the code',
          subtitle: kind.explanation,
          children: [
            GlowField(
              controller: _code,
              focusNode: _focus,
              label: kind.fieldLabel,
              autofocus: true,
              keyboardType: kind.numeric ? TextInputType.number : TextInputType.text,
              inputFormatters: [
                if (kind.numeric) FilteringTextInputFormatter.digitsOnly,
                if (kind.length != null) LengthLimitingTextInputFormatter(kind.length),
              ],
              autofillHints: const [AutofillHints.oneTimeCode],
              textAlign: kind.numeric ? TextAlign.center : TextAlign.start,
              letterSpacing: kind.numeric ? 8 : null,
              errorText: error,
              enabled: !busy,
              onChanged: (value) {
                if (kind.length != null && value.length == kind.length) _submit();
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 28),
            AuthSubmitButton(label: 'Sign in', onPressed: _submit),
            const SizedBox(height: 12),
            if (info.nextType != null)
              FloodGate(
                until: _resendAt,
                builder: (context, remaining) => TextButton(
                  onPressed: remaining != null || busy
                      ? null
                      : () => context.read<AuthBloc>().add(const AuthCodeResendRequested()),
                  child: Text(
                    remaining != null
                        ? 'Send another way in ${formatCountdown(remaining)}'
                        : _describe(info.nextType!, info.phoneNumber).resendLabel,
                  ),
                ),
              ),
            TextButton(
              onPressed: busy ? null : () => context.read<AuthBloc>().add(const AuthPhoneChangeRequested()),
              child: const Text('Wrong number?', style: TextStyle(color: GlowColors.textMuted)),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _CodeKind = ({String explanation, String fieldLabel, String resendLabel, bool numeric, int? length});

_CodeKind _describe(td.AuthenticationCodeType type, String phone) => switch (type) {
  td.AuthenticationCodeTypeTelegramMessage(:final length) => (
    explanation: 'We sent the code to your Telegram app on another device.',
    fieldLabel: 'Code',
    resendLabel: 'Send the code in Telegram',
    numeric: true,
    length: length,
  ),
  td.AuthenticationCodeTypeSms(:final length) => (
    explanation: 'We sent an SMS with the code to $phone.',
    fieldLabel: 'Code',
    resendLabel: 'Send the code by SMS',
    numeric: true,
    length: length,
  ),
  td.AuthenticationCodeTypeSmsWord() => (
    explanation: 'We sent an SMS to $phone. Enter the word it contains.',
    fieldLabel: 'Word',
    resendLabel: 'Send a word by SMS',
    numeric: false,
    length: null,
  ),
  td.AuthenticationCodeTypeSmsPhrase() => (
    explanation: 'We sent an SMS to $phone. Enter the phrase it contains.',
    fieldLabel: 'Phrase',
    resendLabel: 'Send a phrase by SMS',
    numeric: false,
    length: null,
  ),
  td.AuthenticationCodeTypeCall(:final length) => (
    explanation: 'You will get a call that reads out the code.',
    fieldLabel: 'Code',
    resendLabel: 'Call me with the code',
    numeric: true,
    length: length,
  ),
  td.AuthenticationCodeTypeFlashCall() => (
    explanation: 'You will get a short call. Enter the full number that called you.',
    fieldLabel: 'Calling number',
    resendLabel: 'Verify with a call',
    numeric: true,
    length: null,
  ),
  td.AuthenticationCodeTypeMissedCall(:final phoneNumberPrefix, :final length) => (
    explanation: 'You will get a missed call from $phoneNumberPrefix… Enter its last $length digits.',
    fieldLabel: 'Last digits',
    resendLabel: 'Verify with a missed call',
    numeric: true,
    length: length,
  ),
  td.AuthenticationCodeTypeFragment(:final url, :final length) => (
    explanation: 'Open $url to get your code.',
    fieldLabel: 'Code',
    resendLabel: 'Get the code on Fragment',
    numeric: true,
    length: length,
  ),
  _ => (
    explanation: 'Enter the code you received.',
    fieldLabel: 'Code',
    resendLabel: 'Send the code another way',
    numeric: true,
    length: null,
  ),
};
