import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/config/native_licenses.dart';
import '../../../../core/storage/app_preferences.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_button.dart';
import '../../../auth/bloc/auth_bloc.dart';
import '../../../auth/domain/account_capabilities.dart';
import '../../../auth/domain/auth_step.dart';
import '../../../home/presentation/widgets/bot_limitations_card.dart';
import '../settings_category.dart';
import '../widgets/general_settings.dart';
import '../widgets/settings_section.dart';
import 'settings_category_screen.dart';

/// Settings sections contributed by other features (proxy, storage,
/// Whisper, search index…), provided by the composition root.
class SettingsEntries {
  const SettingsEntries(this.build);
  final List<SettingsEntry> Function(BuildContext context) build;
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final step = context.select((AuthBloc b) => b.state.step);
    if (step is! AuthReady) return const SizedBox.shrink();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SettingsHub(me: step.me, caps: step.capabilities),
      ),
    );
  }
}

/// The top Settings page: the account, one row per category, About, Log out.
class SettingsHub extends StatelessWidget {
  const SettingsHub({super.key, required this.me, required this.caps});

  final td.User me;
  final AccountCapabilities caps;

  List<SettingsEntry> _entries(BuildContext context) {
    List<SettingsEntry> features;
    try {
      features = context.read<SettingsEntries>().build(context);
    } on ProviderNotFoundException {
      features = const [];
    }
    return [
      SettingsEntry(SettingsCategory.privacy, (_) => const PrivacySettings(), forBots: false),
      SettingsEntry(SettingsCategory.chats, (_) => const LinkSettings()),
      SettingsEntry(SettingsCategory.chats, (_) => const StorySettings(), forBots: false),
      SettingsEntry(
        SettingsCategory.chats,
        (_) => ChannelAdsSettings(isPremium: me.isPremium),
        forBots: false,
      ),
      SettingsEntry(SettingsCategory.media, (_) => const MediaPlaybackSettings()),
      ...features,
    ].where((e) => e.forBots || !caps.isBot).toList();
  }

  String _summary(SettingsCategory c, AppPreferences prefs) => switch (c) {
    SettingsCategory.privacy => _privacySummary(prefs),
    SettingsCategory.chats => caps.isBot ? 'Link previews' : 'Links, stories and channel ads',
    SettingsCategory.media => 'Playback ${prefs.playbackSpeed.toStringAsFixed(2)}× · offline speech',
    SettingsCategory.notifications => 'Staying connected without Google push',
    SettingsCategory.data => 'Media cache and local message search',
    SettingsCategory.connection => 'Proxy and phone calls',
  };

  static String _privacySummary(AppPreferences prefs) {
    if (prefs.ghostMode) return 'Ghost mode on';
    final hidden = [
      prefs.hideReadReceipts,
      prefs.hideTyping,
      prefs.appearOffline,
      prefs.hideStoryViews,
    ].where((v) => v).length;
    return hidden == 0 ? 'Read receipts, typing, online status' : '$hidden of 4 hidden';
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<AppPreferences>();
    final entries = _entries(context);
    final categories = [
      for (final c in SettingsCategory.values)
        if (entries.any((e) => e.category == c)) c,
    ];
    return ListenableBuilder(
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
          SettingsSection(
            title: 'Settings',
            children: [
              for (final c in categories)
                _CategoryRow(
                  category: c,
                  summary: _summary(c, prefs),
                  onTap: () => Navigator.of(context).push(
                    SettingsCategoryScreen.route(c, [
                      for (final e in entries)
                        if (e.category == c) e,
                    ]),
                  ),
                ),
            ],
          ),
          SettingsSection(
            title: 'Lumina',
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline_rounded, color: GlowColors.violet),
                title: const Text('About & licenses'),
                subtitle: const Text('Free software under the GNU GPL v3'),
                trailing: const Icon(Icons.chevron_right_rounded, color: GlowColors.textMuted),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Lumina',
                  applicationLegalese: luminaLegalese,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          GlowButton.warm(label: 'Log out', onPressed: () => _confirmLogout(context)),
        ],
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

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.summary, required this.onTap});

  final SettingsCategory category;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(category.icon, color: GlowColors.cyan),
    title: Text(category.title),
    subtitle: Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: const Icon(Icons.chevron_right_rounded, color: GlowColors.textMuted),
    onTap: onTap,
  );
}
