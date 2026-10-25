import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_background.dart';
import '../../../../core/widgets/glow_sigil.dart';
import '../../bloc/auth_bloc.dart';
import 'notice_banner.dart';

/// Optional actions the app adds to auth screens (provided by the
/// composition root).
class AuthExtras {
  const AuthExtras({this.openProxy});

  /// Proxy settings, needed before login where Telegram is blocked.
  final void Function(BuildContext context)? openProxy;
}

/// Shared frame for every auth screen: drifting backdrop, sigil, title,
/// subtitle, the pending notice (if any) and the screen's form.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, required this.children, this.subtitle});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final notice = context.select((AuthBloc b) => b.state.notice);
    AuthExtras extras;
    try {
      extras = context.read<AuthExtras>();
    } on ProviderNotFoundException {
      extras = const AuthExtras();
    }
    return Scaffold(
      body: GlowBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (extras.openProxy != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: 'Proxy settings',
                          icon: const Icon(Icons.vpn_lock_rounded, color: GlowColors.textMuted),
                          onPressed: () => extras.openProxy!(context),
                        ),
                      ),
                    const Center(child: GlowSigil()),
                    const SizedBox(height: 28),
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: 0.2),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        subtitle!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: GlowColors.textMuted, fontSize: 15, height: 1.4),
                      ),
                    ],
                    if (notice != null) ...[
                      const SizedBox(height: 20),
                      NoticeBanner(
                        text: notice,
                        onDismiss: () => context.read<AuthBloc>().add(const AuthNoticeDismissed()),
                      ),
                    ],
                    const SizedBox(height: 32),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
