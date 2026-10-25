import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/config/native_licenses.dart';
import '../../../../core/storage/app_preferences.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_button.dart';
import '../../../auth/bloc/auth_bloc.dart';
import '../../../auth/domain/auth_step.dart';
import '../../../conversation/data/messages_repository.dart';
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
                      value: prefs.ghostMode,
                      onChanged: (v) => prefs.ghostMode = v,
                      secondary: Icon(
                        Icons.blur_on_rounded,
                        color: prefs.ghostMode ? GlowColors.cyan : GlowColors.textMuted,
                      ),
                      title: const Text('Ghost mode'),
                      subtitle: const Text('No read receipts, typing, online status or story views'),
                    ),
                    const Divider(height: 1, color: GlowColors.outline),
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
                    SwitchListTile(
                      value: prefs.hideStoryViews,
                      onChanged: (v) => prefs.hideStoryViews = v,
                      title: const Text('View stories anonymously'),
                      subtitle: const Text('Opening a story doesn’t mark it as viewed'),
                    ),
                  ],
                ),
              if (!caps.isBot) _AdsSection(isPremium: me.isPremium, prefs: prefs),
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
              SettingsSection(
                title: 'Links',
                children: [
                  SwitchListTile(
                    value: prefs.linkPreviewsOnSend,
                    onChanged: (v) => prefs.linkPreviewsOnSend = v,
                    title: const Text('Link previews when sending'),
                    subtitle: const Text('Shows the preview above the composer; tap ✕ to send one message without it'),
                  ),
                  SwitchListTile(
                    value: prefs.showLinkPreviews,
                    onChanged: (v) => prefs.showLinkPreviews = v,
                    title: const Text('Show link previews in chats'),
                    subtitle: const Text('Including Instant View for articles'),
                  ),
                  SwitchListTile(
                    value: prefs.openLinksExternally,
                    onChanged: (v) => prefs.openLinksExternally = v,
                    title: const Text('Open links in browser app'),
                    subtitle: const Text('Off: a Chromium Custom Tab over Lumina (no embedded WebView)'),
                  ),
                ],
              ),
              ...extras,
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('About & licenses'),
                subtitle: const Text('Free software under the GNU GPL v3'),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Lumina',
                  applicationLegalese: luminaLegalese,
                ),
              ),
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

class _AdsSection extends StatelessWidget {
  const _AdsSection({required this.isPremium, required this.prefs});

  final bool isPremium;
  final AppPreferences prefs;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'Channels',
      children: [
        SwitchListTile(
          value: prefs.hideSponsored,
          onChanged: (v) async {
            prefs.hideSponsored = v;
            if (isPremium) {
              // Telegram's own ad-free switch for Premium accounts.
              await context.read<MessagesRepository>().setSponsoredEnabled(!v).catchError((_) {});
            }
          },
          title: const Text('Hide channel ads'),
          subtitle: Text(
            isPremium
                ? 'Uses Telegram Premium’s ad-free setting.'
                : 'Hidden on this device only. Telegram’s API terms ask apps to show sponsored '
                      'messages, so Telegram may restrict apps whose users hide them.',
          ),
        ),
      ],
    );
  }
}
