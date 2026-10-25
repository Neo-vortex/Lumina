import 'package:flutter/material.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../settings/presentation/widgets/settings_section.dart';
import '../screens/proxy_screen.dart';

class ConnectionSettings extends StatelessWidget {
  const ConnectionSettings({super.key});

  @override
  Widget build(BuildContext context) => SettingsSection(
    title: 'Connection',
    children: [
      ListTile(
        leading: const Icon(Icons.vpn_lock_rounded, color: GlowColors.cyan),
        title: const Text('Proxy'),
        subtitle: const Text('SOCKS5, HTTP and MTProto'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push(ProxyScreen.route()),
      ),
    ],
  );
}
