import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/app_preferences.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../conversation/data/messages_repository.dart';
import 'settings_section.dart';

/// Settings → Privacy.
class PrivacySettings extends StatelessWidget {
  const PrivacySettings({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<AppPreferences>();
    return SettingsSection(
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
    );
  }
}

/// Settings → Chats: link previews and how links open.
class LinkSettings extends StatelessWidget {
  const LinkSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<AppPreferences>();
    return SettingsSection(
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
    );
  }
}

/// Settings → Chats: stories.
class StorySettings extends StatelessWidget {
  const StorySettings({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<AppPreferences>();
    return SettingsSection(
      title: 'Stories',
      children: [
        SwitchListTile(
          value: prefs.hideStories,
          onChanged: (v) => prefs.hideStories = v,
          title: const Text('Hide stories'),
          subtitle: const Text('No story halos or story prompts anywhere'),
        ),
      ],
    );
  }
}

/// Settings → Chats: sponsored messages in channels.
class ChannelAdsSettings extends StatelessWidget {
  const ChannelAdsSettings({super.key, required this.isPremium});

  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<AppPreferences>();
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

/// Settings → Media & voice: playback.
class MediaPlaybackSettings extends StatelessWidget {
  const MediaPlaybackSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<AppPreferences>();
    return SettingsSection(
      title: 'Playback',
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
    );
  }
}
