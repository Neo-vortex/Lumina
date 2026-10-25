import 'package:flutter/material.dart';

import '../../bloc/auth_bloc.dart';
import '../widgets/single_field_step.dart';

class EmailAddressScreen extends StatelessWidget {
  const EmailAddressScreen({super.key});

  @override
  Widget build(BuildContext context) => const SingleFieldStep(
    title: 'Add an email',
    subtitle: 'Telegram requires an email address to finish signing in.',
    label: 'Email',
    keyboardType: TextInputType.emailAddress,
    autofillHints: [AutofillHints.email],
    toEvent: AuthEmailAddressSubmitted.new,
  );
}
