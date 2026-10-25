import 'package:flutter/material.dart';

import '../../bloc/auth_bloc.dart';
import '../../domain/auth_step.dart';
import '../widgets/single_field_step.dart';

class PasswordScreen extends StatelessWidget {
  const PasswordScreen({super.key, required this.step});

  final AuthWaitPassword step;

  @override
  Widget build(BuildContext context) => SingleFieldStep(
    title: 'Two-step verification',
    subtitle: step.hint.isEmpty
        ? 'Your account is protected with an additional password.'
        : 'Your account is protected with an additional password.\nHint: ${step.hint}',
    label: 'Password',
    obscure: true,
    autofillHints: const [AutofillHints.password],
    buttonLabel: 'Unlock',
    toEvent: AuthPasswordSubmitted.new,
  );
}
