import 'package:flutter/material.dart';

import '../../bloc/auth_bloc.dart';
import '../../domain/auth_step.dart';
import '../widgets/single_field_step.dart';

class EmailCodeScreen extends StatelessWidget {
  const EmailCodeScreen({super.key, required this.step});

  final AuthWaitEmailCode step;

  @override
  Widget build(BuildContext context) => SingleFieldStep(
    title: 'Check your email',
    subtitle: 'Enter the ${step.info.length}-digit code sent to ${step.info.emailAddressPattern}.',
    label: 'Code',
    keyboardType: TextInputType.number,
    autofillHints: const [AutofillHints.oneTimeCode],
    toEvent: AuthEmailCodeSubmitted.new,
  );
}
