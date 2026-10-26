import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../data/proxy_config.dart';
import '../../data/proxy_repository.dart';
import '../screens/proxy_screen.dart';

/// Chat list header button: glows while a proxy is on and opens the proxy
/// list (scan, paste, switch).
class ProxyButton extends StatelessWidget {
  const ProxyButton({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ProxyRepository>();
    return ValueListenableBuilder<ProxyConfig?>(
      valueListenable: repo.activeProxy,
      builder: (context, active, _) => IconButton(
        tooltip: active == null ? 'Proxy: off' : 'Proxy: ${active.server}',
        icon: Icon(
          active == null ? Icons.shield_outlined : Icons.shield_rounded,
          color: active == null ? null : GlowColors.cyan,
          shadows: active == null ? null : const [Shadow(color: GlowColors.cyan, blurRadius: 12)],
        ),
        onPressed: () => Navigator.of(context).push(ProxyScreen.route()),
      ),
    );
  }
}
