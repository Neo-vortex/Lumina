import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/app_preferences.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../settings/presentation/widgets/settings_section.dart';
import '../../data/proxy_config.dart';
import '../../data/proxy_repository.dart';
import '../screens/proxy_screen.dart';

class ConnectionSettings extends StatefulWidget {
  const ConnectionSettings({super.key});

  @override
  State<ConnectionSettings> createState() => _ConnectionSettingsState();
}

class _ConnectionSettingsState extends State<ConnectionSettings> {
  SavedProxy? _active;
  var _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    SavedProxy? active;
    try {
      active = await context.read<ProxyRepository>().active();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _active = active;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<AppPreferences>();
    return ListenableBuilder(
      listenable: prefs.changes,
      builder: (context, _) => SettingsSection(
        title: 'Connection',
        children: [
          ListTile(
            leading: const Icon(Icons.vpn_lock_rounded, color: GlowColors.cyan),
            title: const Text('Proxy'),
            subtitle: const Text('SOCKS5, HTTP and MTProto'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              await Navigator.of(context).push(ProxyScreen.route());
              await _load();
            },
          ),
          SwitchListTile(
            value: prefs.callsUseProxy,
            onChanged: (v) => prefs.callsUseProxy = v,
            title: const Text('Use proxy for calls'),
            subtitle: _loaded ? Text(ConnectionSettingsNotes.note(_active, on: prefs.callsUseProxy)) : null,
          ),
        ],
      ),
    );
  }
}

/// Why calls do or don't go through the proxy (Settings → Connection).
abstract final class ConnectionSettingsNotes {
  static String note(SavedProxy? active, {required bool on}) {
    if (!on) return 'Calls connect directly (peer-to-peer allowed)';
    if (active == null) return 'No proxy is on, so calls connect directly';
    return switch (active.config.kind) {
      ProxyKind.socks5 => 'Calls go through ${active.config.server} (no peer-to-peer)',
      ProxyKind.http || ProxyKind.mtproto =>
        'The active proxy is ${active.config.kind == ProxyKind.http ? 'HTTP' : 'MTProto'}; only SOCKS5 proxies can carry calls',
    };
  }
}
