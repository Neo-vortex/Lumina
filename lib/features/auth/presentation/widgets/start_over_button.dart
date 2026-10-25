import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../bloc/auth_bloc.dart';

/// Abandons a login in progress (closes and recreates the TDLib client).
class StartOverButton extends StatelessWidget {
  const StartOverButton({super.key});

  @override
  Widget build(BuildContext context) {
    final busy = context.select((AuthBloc b) => b.state.busy);
    return TextButton(
      onPressed: busy ? null : () => context.read<AuthBloc>().add(const AuthLogOutRequested()),
      child: const Text('Start over', style: TextStyle(color: GlowColors.textMuted)),
    );
  }
}
