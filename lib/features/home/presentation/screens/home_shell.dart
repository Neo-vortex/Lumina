import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../chats/bloc/chat_list_cubit.dart';
import '../../../chats/data/chats_repository.dart';
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
      create: (context) => ChatListCubit(repository: context.read<ChatsRepository>())..start(),
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
