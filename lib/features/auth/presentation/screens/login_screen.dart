import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/motion.dart';
import '../../../../core/widgets/glow_field.dart';
import '../../bloc/auth_bloc.dart';
import '../../domain/auth_step.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/auth_submit_button.dart';
import '../widgets/login_mode_toggle.dart';
import '../widgets/start_over_button.dart';

/// Phone-number and bot-token entry. Both are valid only while TDLib waits
/// for a phone number, so they share a screen.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _token = TextEditingController();
  var _mode = LoginMode.phone;

  @override
  void dispose() {
    _phone.dispose();
    _token.dispose();
    super.dispose();
  }

  void _submit() {
    final bloc = context.read<AuthBloc>();
    switch (_mode) {
      case LoginMode.phone:
        if (_phone.text.trim().isNotEmpty) bloc.add(AuthPhoneNumberSubmitted(_phone.text));
      case LoginMode.bot:
        if (_token.text.trim().isNotEmpty) bloc.add(AuthBotTokenSubmitted(_token.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = context.select((AuthBloc b) => b.state.inlineError);
    final busy = context.select((AuthBloc b) => b.state.busy);
    // TDLib is further along; phone entry is only being shown again.
    final loginPending = context.select((AuthBloc b) => b.state.step is! AuthWaitPhone);

    return AuthScaffold(
      title: 'Welcome to Lumina',
      subtitle: _mode == LoginMode.phone
          ? 'Sign in with your phone number. We will send you a code.'
          : 'Paste the token @BotFather gave your bot.',
      children: [
        LoginModeToggle(mode: _mode, onChanged: (mode) => setState(() => _mode = mode)),
        const SizedBox(height: 28),
        AnimatedSwitcher(
          duration: Motion.standard,
          switchInCurve: Motion.enter,
          switchOutCurve: Motion.exit,
          child: _mode == LoginMode.phone
              ? GlowField(
                  key: const ValueKey(LoginMode.phone),
                  controller: _phone,
                  label: 'Phone number',
                  hint: '+1 555 010 0000',
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s()-]'))],
                  errorText: error,
                  enabled: !busy,
                  onSubmitted: (_) => _submit(),
                )
              : GlowField(
                  key: const ValueKey(LoginMode.bot),
                  controller: _token,
                  label: 'Bot token',
                  hint: '123456789:AA…',
                  keyboardType: TextInputType.visiblePassword,
                  obscure: true,
                  errorText: error,
                  enabled: !busy,
                  onSubmitted: (_) => _submit(),
                ),
        ),
        const SizedBox(height: 28),
        AuthSubmitButton(label: 'Continue', onPressed: _submit),
        if (loginPending) ...[const SizedBox(height: 12), const StartOverButton()],
      ],
    );
  }
}
