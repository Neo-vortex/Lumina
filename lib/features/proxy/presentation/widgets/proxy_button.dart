import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../data/proxy_config.dart';
import '../../data/proxy_repository.dart';
import '../screens/proxy_screen.dart';

/// Chat list header button, shown only while connected through a proxy:
/// a glowing shield that opens the proxy list (scan, paste, switch). With no
/// proxy, the connection status capsule is the way in.
class ProxyButton extends StatelessWidget {
  const ProxyButton({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ProxyRepository>();
    return ValueListenableBuilder<ProxyConfig?>(
      valueListenable: repo.activeProxy,
      builder: (context, active, _) => active == null
          ? const SizedBox.shrink()
          : IconButton(
              tooltip: 'Proxy: ${active.server}',
              icon: const Icon(
                Icons.shield_rounded,
                color: GlowColors.cyan,
                shadows: [Shadow(color: GlowColors.cyan, blurRadius: 12)],
              ),
              onPressed: () => Navigator.of(context).push(ProxyScreen.route()),
            ),
    );
  }
}
