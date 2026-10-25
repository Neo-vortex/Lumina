import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth_bloc.dart';

/// System back on a mid-login screen returns to phone entry instead of
/// closing the app (UX-14). Declared up front, as predictive back requires.
class BackToPhoneScope extends StatelessWidget {
  const BackToPhoneScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.read<AuthBloc>().add(const AuthPhoneChangeRequested());
      },
      child: child,
    );
  }
}
