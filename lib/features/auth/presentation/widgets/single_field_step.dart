import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/glow_field.dart';
import '../../bloc/auth_bloc.dart';
import 'auth_scaffold.dart';
import 'auth_submit_button.dart';
import 'back_to_phone_scope.dart';
import 'start_over_button.dart';

/// A one-field mid-login step (password, email, email code).
class SingleFieldStep extends StatefulWidget {
  const SingleFieldStep({
    super.key,
    required this.title,
    required this.subtitle,
    required this.label,
    required this.toEvent,
    this.obscure = false,
    this.keyboardType,
    this.autofillHints,
    this.buttonLabel = 'Continue',
  });

  final String title;
  final String subtitle;
  final String label;
  final AuthSubmitted Function(String value) toEvent;
  final bool obscure;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final String buttonLabel;

  @override
  State<SingleFieldStep> createState() => _SingleFieldStepState();
}

class _SingleFieldStepState extends State<SingleFieldStep> {
  final _value = TextEditingController();

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _submit() {
    if (_value.text.isNotEmpty) context.read<AuthBloc>().add(widget.toEvent(_value.text));
  }

  @override
  Widget build(BuildContext context) {
    final error = context.select((AuthBloc b) => b.state.inlineError);
    final busy = context.select((AuthBloc b) => b.state.busy);
    return BackToPhoneScope(
      child: AuthScaffold(
        title: widget.title,
        subtitle: widget.subtitle,
        children: [
          GlowField(
            controller: _value,
            label: widget.label,
            autofocus: true,
            obscure: widget.obscure,
            keyboardType: widget.keyboardType,
            autofillHints: widget.autofillHints,
            errorText: error,
            enabled: !busy,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 28),
          AuthSubmitButton(label: widget.buttonLabel, onPressed: _submit),
          const SizedBox(height: 12),
          const StartOverButton(),
        ],
      ),
    );
  }
}
