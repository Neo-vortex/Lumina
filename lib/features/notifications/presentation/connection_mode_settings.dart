import 'package:flutter/material.dart';

import '../../../core/platform/system_channel.dart';
import '../../../core/theme/glow_colors.dart';
import '../../settings/presentation/widgets/settings_section.dart';
import '../data/notification_center.dart';

/// Settings → Notifications: how Lumina stays reachable without Google push.
class ConnectionModeSettings extends StatefulWidget {
  const ConnectionModeSettings({super.key});

  @override
  State<ConnectionModeSettings> createState() => _ConnectionModeSettingsState();
}

class _ConnectionModeSettingsState extends State<ConnectionModeSettings> with WidgetsBindingObserver {
  String? _mode;

  /// False while Android blocks Lumina's notifications.
  bool _allowed = true;

  Future<void> _checkAllowed() async {
    final ok = await const SystemChannel().notificationsEnabled();
    if (mounted) setState(() => _allowed = ok);
  }

  Future<void> _allow() async {
    const system = SystemChannel();
    if (!await system.requestNotifications()) await system.openNotificationSettings();
    await _checkAllowed();
  }

  // Back from the system settings page.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAllowed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  static const _modes = [
    (
      'connected',
      'Always connected',
      'Messages and calls arrive instantly. Shows a silent "Lumina is connected" notification.',
    ),
    (
      'saver',
      'Battery saver',
      'Checks for messages about every 15 minutes. Calls ring only while Lumina is open.',
    ),
    ('off', 'Only while open', 'No notifications when Lumina is closed.'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAllowed();
    ChannelNotificationSink.backgroundMode().then((m) {
      if (mounted) setState(() => _mode = m);
    });
  }

  Future<void> _set(String? mode) async {
    if (mode == null) return;
    setState(() => _mode = mode);
    await ChannelNotificationSink.setBackgroundMode(mode);
    if (mode != 'off' && !_allowed) await _allow();
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode;
    if (mode == null) return const SizedBox.shrink();
    return SettingsSection(
      title: 'Notifications',
      children: [
        if (!_allowed)
          ListTile(
            leading: const Icon(Icons.notifications_off_rounded, color: GlowColors.error),
            title: const Text('Notifications are blocked'),
            subtitle: const Text('Android isn\'t letting Lumina show new messages. Tap to allow.'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _allow,
          ),
        const ListTile(
          leading: Icon(Icons.notifications_active_rounded, color: GlowColors.cyan),
          title: Text('Without Google push'),
          subtitle: Text('Lumina keeps its own connection to Telegram instead of Firebase.'),
        ),
        RadioGroup<String>(
          groupValue: mode,
          onChanged: _set,
          child: Column(
            children: [
              for (final (value, title, subtitle) in _modes)
                RadioListTile<String>(value: value, title: Text(title), subtitle: Text(subtitle)),
            ],
          ),
        ),
      ],
    );
  }
}
