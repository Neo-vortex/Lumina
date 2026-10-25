import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/flood_gate.dart';
import '../../../../core/widgets/glow_button.dart';
import '../../bloc/auth_bloc.dart';

/// Primary auth action: shows progress while busy and a countdown while
/// flood-waiting, and is disabled in both cases (UX-21).
class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final busy = context.select((AuthBloc b) => b.state.busy);
    final floodUntil = context.select((AuthBloc b) => b.state.floodUntil);
    return FloodGate(
      until: floodUntil,
      builder: (context, remaining) => GlowButton(
        label: remaining != null ? 'Wait ${formatCountdown(remaining)}' : label,
        busy: busy,
        onPressed: remaining != null ? null : onPressed,
      ),
    );
  }
}
