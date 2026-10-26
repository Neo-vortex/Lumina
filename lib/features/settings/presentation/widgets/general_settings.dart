import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/app_preferences.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_sheet.dart';
import '../../../conversation/data/messages_repository.dart';
import '../screens/swipe_settings_screen.dart';
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
class GestureSettings extends StatelessWidget {
  const GestureSettings({super.key});

  @override
  Widget build(BuildContext context) => SettingsSection(
    title: 'Gestures',
    children: [
      ListTile(
        leading: const Icon(Icons.swipe_rounded, color: GlowColors.violet),
        title: const Text('Swipe gestures'),
        subtitle: const Text('What swiping left or right does on messages and chats'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push(SwipeSettingsScreen.route()),
      ),
    ],
  );
}

/// Quick reactions (shown first on the message menu) and whether emoji,
/// reactions and custom emoji animate.
class ReactionSettings extends StatelessWidget {
  const ReactionSettings({super.key});

  static const choices = [
    '❤️',
    '👍',
    '🔥',
    '😂',
    '😮',
    '😢',
    '🙏',
    '👏',
    '🎉',
    '🤔',
    '👎',
    '💯',
    '😍',
    '🤩',
    '😁',
    '🥰',
    '😱',
    '🤯',
    '😡',
    '🤝',
    '👌',
    '⚡',
    '🍓',
    '🏆',
  ];

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<AppPreferences>();
    return ListenableBuilder(
      listenable: prefs.changes,
      builder: (context, _) => SettingsSection(
        title: 'Reactions & emoji',
        children: [
          ListTile(
            leading: const Icon(Icons.add_reaction_rounded, color: GlowColors.violet),
            title: const Text('Quick reactions'),
            subtitle: Text(prefs.quickReactions.join('  '), style: const TextStyle(fontSize: 18)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _pick(context, prefs),
          ),
          SwitchListTile(
            value: prefs.animatedEmoji,
            onChanged: (v) => prefs.animatedEmoji = v,
            title: const Text('Animated emoji'),
            subtitle: const Text('Reactions and custom emoji play their animation; off shows them static'),
          ),
        ],
      ),
    );
  }

  Future<void> _pick(BuildContext context, AppPreferences prefs) async {
    final picked = [...prefs.quickReactions];
    final result = await showGlowSheet<List<String>>(
      context,
      title: 'Quick reactions',
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pick up to 5, in the order they should appear (${picked.length}/5)',
                style: const TextStyle(color: GlowColors.textMuted),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in choices)
                    InkResponse(
                      radius: 28,
                      onTap: () => setState(() {
                        if (picked.contains(e)) {
                          picked.remove(e);
                        } else if (picked.length < 5) {
                          picked.add(e);
                        }
                      }),
                      child: Container(
                        width: 50,
                        height: 50,
                        alignment: Alignment.center,
                        decoration: picked.contains(e)
                            ? BoxDecoration(
                                shape: BoxShape.circle,
                                color: GlowColors.violet.withValues(alpha: 0.22),
                                border: Border.all(color: GlowColors.violet),
                              )
                            : null,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Text(e, style: const TextStyle(fontSize: 26)),
                            if (picked.contains(e))
                              Positioned(
                                right: -8,
                                top: -6,
                                child: Text(
                                  '${picked.indexOf(e) + 1}',
                                  style: const TextStyle(
                                    color: GlowColors.violet,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(onPressed: () => setState(picked.clear), child: const Text('Clear')),
                  const Spacer(),
                  FilledButton(
                    onPressed: picked.isEmpty ? null : () => Navigator.pop(context, picked),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null) prefs.quickReactions = result;
  }
}

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
