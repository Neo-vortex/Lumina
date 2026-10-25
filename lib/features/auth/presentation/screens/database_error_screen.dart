import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/glow_button.dart';
import '../../bloc/auth_bloc.dart';
import '../../domain/auth_step.dart';
import '../widgets/auth_scaffold.dart';

/// Recovery for a corrupt database or lost encryption key (spec §10.1).
class DatabaseErrorScreen extends StatelessWidget {
  const DatabaseErrorScreen({super.key, required this.step});

  final AuthDatabaseError step;

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Local data unreadable',
      subtitle:
          'The on-device Telegram database could not be opened (${step.message}).\n'
          'Resetting deletes cached chats and media on this device only; your account and cloud '
          'messages are kept, and you will sign in again.',
      children: [
        GlowButton.warm(
          label: 'Reset local data',
          onPressed: () => context.read<AuthBloc>().add(const AuthLocalDataResetRequested()),
        ),
      ],
    );
  }
}
