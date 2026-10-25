import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_field.dart';
import '../../bloc/auth_bloc.dart';
import '../../domain/auth_step.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/auth_submit_button.dart';
import '../widgets/back_to_phone_scope.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key, required this.step});

  final AuthWaitRegistration step;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _first = TextEditingController();
  final _last = TextEditingController();

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  void _submit() {
    if (_first.text.trim().isEmpty) return;
    context.read<AuthBloc>().add(AuthRegistrationSubmitted(firstName: _first.text, lastName: _last.text));
  }

  @override
  Widget build(BuildContext context) {
    final error = context.select((AuthBloc b) => b.state.inlineError);
    final busy = context.select((AuthBloc b) => b.state.busy);
    return BackToPhoneScope(
      child: AuthScaffold(
        title: 'Create your profile',
        subtitle: 'This number has no Telegram account yet.',
        children: [
          GlowField(
            controller: _first,
            label: 'First name',
            autofocus: true,
            autofillHints: const [AutofillHints.givenName],
            enabled: !busy,
            errorText: error,
          ),
          const SizedBox(height: 16),
          GlowField(
            controller: _last,
            label: 'Last name (optional)',
            autofillHints: const [AutofillHints.familyName],
            enabled: !busy,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 20),
          if (widget.step.termsOfService.isNotEmpty)
            ExpansionTile(
              title: const Text('Terms of Service', style: TextStyle(fontSize: 14)),
              iconColor: GlowColors.cyan,
              collapsedIconColor: GlowColors.textMuted,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    widget.step.termsOfService,
                    style: const TextStyle(color: GlowColors.textMuted, fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 20),
          AuthSubmitButton(label: 'Agree and continue', onPressed: _submit),
        ],
      ),
    );
  }
}
