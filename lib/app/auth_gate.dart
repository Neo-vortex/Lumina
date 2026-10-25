import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/theme/motion.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/auth/domain/auth_step.dart';
import '../features/auth/presentation/screens/code_screen.dart';
import '../features/auth/presentation/screens/database_error_screen.dart';
import '../features/auth/presentation/screens/email_address_screen.dart';
import '../features/auth/presentation/screens/email_code_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/missing_credentials_screen.dart';
import '../features/auth/presentation/screens/other_device_screen.dart';
import '../features/auth/presentation/screens/password_screen.dart';
import '../features/auth/presentation/screens/pulse_screen.dart';
import '../features/auth/presentation/screens/registration_screen.dart';
import '../features/home/presentation/screens/home_shell.dart';

/// Picks the screen for the current auth step. Only the visible step is
/// selected, so typing, busy flags or errors never rebuild the gate.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final step = context.select((AuthBloc b) => b.state.visibleStep);
    final Widget screen = switch (step) {
      AuthBooting() => const PulseScreen(caption: 'Waking up…'),
      AuthClosing() => const PulseScreen(caption: 'Closing session…'),
      AuthMissingApiCredentials() => const MissingCredentialsScreen(),
      AuthDatabaseError() => DatabaseErrorScreen(step: step),
      AuthWaitPhone() => const LoginScreen(),
      AuthWaitCode() => CodeScreen(step: step),
      AuthWaitEmailAddress() => const EmailAddressScreen(),
      AuthWaitEmailCode() => EmailCodeScreen(step: step),
      AuthWaitPassword() => PasswordScreen(step: step),
      AuthWaitRegistration() => RegistrationScreen(step: step),
      AuthWaitOtherDevice() => OtherDeviceScreen(step: step),
      AuthReady() => const HomeShell(),
    };
    final ambient = Motion.ambientEnabled(context);
    return AnimatedSwitcher(
      duration: Motion.screen,
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      // Reduced motion: plain cross-fade, no scale (UX-10).
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ambient ? ScaleTransition(scale: Tween(begin: 0.98, end: 1.0).animate(animation), child: child) : child,
      ),
      child: KeyedSubtree(key: ValueKey(step.runtimeType), child: screen),
    );
  }
}
