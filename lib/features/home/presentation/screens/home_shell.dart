import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../auth/bloc/auth_bloc.dart';
import '../../../auth/domain/auth_step.dart';
import '../../../chats/bloc/lens_cubit.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../chats/presentation/screens/chats_screen.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../widgets/compose_orb.dart';
import '../widgets/glow_nav_bar.dart';

/// Signed-in shell: Chats and Settings tabs around the central compose orb
/// (spec §9.2 navigation).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => LensCubit(
        cache: context.read<TelegramCache>(),
        isBot: switch (context.read<AuthBloc>().state.step) {
          AuthReady(:final capabilities) => capabilities.isBot,
          _ => false,
        },
      ),
      child: PopScope(
        canPop: _tab == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _tab = 0);
        },
        child: Scaffold(
          extendBody: true,
          backgroundColor: GlowColors.background,
          body: IndexedStack(index: _tab, children: const [ChatsScreen(), SettingsScreen()]),
          bottomNavigationBar: GlowNavBar(
            index: _tab,
            onSelect: (i) => setState(() => _tab = i),
            center: const ComposeOrb(),
          ),
        ),
      ),
    );
  }
}
