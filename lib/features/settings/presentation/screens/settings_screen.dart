import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/app_preferences.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_button.dart';
import '../../../auth/bloc/auth_bloc.dart';
import '../../../auth/domain/auth_step.dart';
import '../../../home/presentation/widgets/bot_limitations_card.dart';
import '../widgets/settings_section.dart';

/// Extra settings entries contributed by other features (proxy, storage,
/// Whisper, search index…), provided by the composition root.
class SettingsEntries {
  const SettingsEntries(this.build);
  final List<Widget> Function(BuildContext context) build;
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final step = context.select((AuthBloc b) => b.state.step);
    if (step is! AuthReady) return const SizedBox.shrink();
    final me = step.me;
    final caps = step.capabilities;
    final prefs = context.read<AppPreferences>();
    List<Widget> extras;
    try {
      extras = context.read<SettingsEntries>().build(context);
    } on ProviderNotFoundException {
      extras = const [];
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: prefs.changes,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
            children: [
              Row(
                children: [
                  ChatAvatar.user(me, size: 64),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Display.userName(me),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          [
                            if (caps.isBot) 'Bot account',
                            if (me.usernames?.activeUsernames.firstOrNull case final u?) '@$u',
                            if (me.phoneNumber.isNotEmpty) '+${me.phoneNumber}',
                          ].join(' · '),
                          style: const TextStyle(color: GlowColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (caps.isBot) ...[const SizedBox(height: 20), BotLimitationsCard(caps.limitations)],
              if (!caps.isBot)
                SettingsSection(
                  title: 'Privacy',
                  children: [
                    SwitchListTile(
                      value: prefs.hideReadReceipts,
                      onChanged: (v) => prefs.hideReadReceipts = v,
                      title: const Text('Read without read receipts'),
                      subtitle: const Text('Messages are marked read only when you choose "Mark as read"'),
                    ),
                    SwitchListTile(
                      value: prefs.hideTyping,
                      onChanged: (v) => prefs.hideTyping = v,
                      title: const Text('Hide typing indicator'),
                    ),
                    SwitchListTile(
                      value: prefs.appearOffline,
                      onChanged: (v) => prefs.appearOffline = v,
                      title: const Text('Appear offline'),
                      subtitle: const Text('Don’t show you as online while the app is open'),
                    ),
                  ],
                ),
              if (!caps.isBot)
                SettingsSection(
                  title: 'Stories',
                  children: [
                    SwitchListTile(
                      value: prefs.hideStories,
                      onChanged: (v) => prefs.hideStories = v,
                      title: const Text('Hide stories'),
                      subtitle: const Text('No story halos or story prompts anywhere'),
                    ),
                  ],
                ),
              SettingsSection(
                title: 'Media',
                children: [
                  ListTile(
                    title: const Text('Voice & audio speed'),
                    subtitle: Slider(
                      value: prefs.playbackSpeed,
                      min: 0.5,
                      max: 4,
                      divisions: 14,
                      label: '${prefs.playbackSpeed.toStringAsFixed(2)}×',
                      onChanged: (v) => prefs.playbackSpeed = v,
                    ),
                    trailing: Text('${prefs.playbackSpeed.toStringAsFixed(2)}×'),
                  ),
                  SwitchListTile(
                    value: prefs.autoplayVideos,
                    onChanged: (v) => prefs.autoplayVideos = v,
                    title: const Text('Autoplay videos and GIFs'),
                  ),
                ],
              ),
              ...extras,
              const SizedBox(height: 28),
              GlowButton.warm(label: 'Log out', onPressed: () => _confirmLogout(context)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlowColors.surfaceHigh,
        title: const Text('Log out?'),
        content: const Text('This ends the session and deletes all Telegram data stored on this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out', style: TextStyle(color: GlowColors.coral)),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && context.mounted) context.read<AuthBloc>().add(const AuthLogOutRequested());
  }
}
