import '../../../../core/build/build_flavor.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/app_preferences.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_sheet.dart';
import '../../../../core/widgets/lumina_glass.dart' show GlassMode;
import '../../../conversation/data/messages_repository.dart';
import '../../../backgrounds/presentation/background_picker_screen.dart';
import '../screens/swipe_settings_screen.dart';
import 'settings_section.dart';

/// Settings → Privacy.
class PrivacySettings extends StatelessWidget {
  const PrivacySettings({super.key});

  // Rebuilt on every preference change: this section is a const widget,
  // which the page's own rebuild skips (switches didn't move).
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: context.read<AppPreferences>().changes,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
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
        title: const Text('Gestures'),
        subtitle: const Text('Swipes on messages and chats, and double-tapping a message'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push(SwipeSettingsScreen.route()),
      ),
      ListTile(
        leading: const Icon(Icons.wallpaper_rounded, color: GlowColors.violet),
        title: const Text('Default chat background'),
        subtitle: const Text('For chats without their own background; blur and dim'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push(BackgroundPickerScreen.route()),
      ),
      ListTile(
        leading: const Icon(Icons.auto_awesome_rounded, color: GlowColors.cyan),
        title: const Text('Chat list background'),
        subtitle: const Text('Aurora glow, a photo or a colour behind your chats'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push(BackgroundPickerScreen.route(forChatList: true)),
      ),
      const _TextSizeTile(),
      const _GlassTile(),
    ],
  );
}

/// Text size across the app, with a live preview line.
class _TextSizeTile extends StatelessWidget {
  const _TextSizeTile();

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<AppPreferences>();
    return ListenableBuilder(
      listenable: prefs.changes,
      builder: (context, _) {
        final v = prefs.textScale;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.format_size_rounded, color: GlowColors.violet),
                  const SizedBox(width: 16),
                  const Expanded(child: Text('Text size', style: TextStyle(fontSize: 16))),
                  Text('${(v * 100).round()}%', style: const TextStyle(color: GlowColors.textMuted)),
                ],
              ),
              Row(
                children: [
                  const Text('A', style: TextStyle(fontSize: 12, color: GlowColors.textMuted)),
                  Expanded(
                    child: Slider(
                      value: v,
                      min: 0.85,
                      max: 1.4,
                      divisions: 11,
                      onChanged: (x) => prefs.textScale = double.parse(x.toStringAsFixed(2)),
                    ),
                  ),
                  const Text('A', style: TextStyle(fontSize: 22, color: GlowColors.textMuted)),
                ],
              ),
              if (v != 1.0)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => prefs.textScale = 1.0, child: const Text('Reset')),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Liquid glass, light blur or solid chat chrome.
class _GlassTile extends StatelessWidget {
  const _GlassTile();

  static String _label(GlassMode m) => switch (m) {
    GlassMode.light => 'Light glass (smooth)',
    GlassMode.full => 'Real glass (liquid, heavier)',
    GlassMode.adaptive => 'Real glass while still, light while scrolling',
    GlassMode.off => 'Off (solid, smoothest)',
  };

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<AppPreferences>();
    return ListenableBuilder(
      listenable: prefs.changes,
      builder: (context, _) => ListTile(
        leading: const Icon(Icons.blur_on_rounded, color: GlowColors.cyan),
        title: const Text('Glass effects'),
        subtitle: Text('Chat header and composer: ${_label(prefs.glassMode)}'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () async {
          final m = await showGlowSheet<GlassMode>(
            context,
            title: 'Glass effects',
            builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in GlassMode.values)
                  ListTile(
                    title: Text(_label(m)),
                    trailing: m == prefs.glassMode
                        ? const Icon(Icons.check_rounded, color: GlowColors.violet)
                        : null,
                    onTap: () => Navigator.pop(context, m),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          );
          if (m != null) prefs.glassMode = m;
        },
      ),
    );
  }
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
          if (kOnDeviceLlm)
            SwitchListTile(
              value: prefs.aiReactionSuggestion,
              onChanged: (v) => prefs.aiReactionSuggestion = v,
              title: const Text('AI reaction suggestion'),
              subtitle: const Text(
                'When you tap a message, the on-device AI suggests one reaction (marked ✨)',
              ),
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

/// Location messages: map previews and which app opens them.
class MapSettings extends StatelessWidget {
  const MapSettings({super.key});

  static const apps = {'ask': 'Ask each time', 'google': 'Google Maps', 'osm': 'OpenStreetMap'};

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<AppPreferences>();
    return ListenableBuilder(
      listenable: prefs.changes,
      builder: (context, _) => SettingsSection(
        title: 'Maps',
        children: [
          SwitchListTile(
            value: prefs.mapPreviews,
            onChanged: (v) => prefs.mapPreviews = v,
            title: const Text('Map previews'),
            subtitle: const Text('A map on location messages, rendered by Telegram (no third party)'),
          ),
          ListTile(
            title: const Text('Open locations in'),
            subtitle: Text(apps[prefs.mapApp] ?? apps['ask']!),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              final pick = await showGlowSheet<String>(
                context,
                title: 'Open locations in',
                builder: (context) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in apps.entries)
                      ListTile(
                        title: Text(e.value),
                        trailing: e.key == prefs.mapApp
                            ? const Icon(Icons.check_rounded, color: GlowColors.violet)
                            : null,
                        onTap: () => Navigator.pop(context, e.key),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
              if (pick != null) prefs.mapApp = pick;
            },
          ),
        ],
      ),
    );
  }
}

class LinkSettings extends StatelessWidget {
  const LinkSettings({super.key});

  // Rebuilt on every preference change: this section is a const widget,
  // which the page's own rebuild skips (switches didn't move).
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: context.read<AppPreferences>().changes,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
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

  // Rebuilt on every preference change: this section is a const widget,
  // which the page's own rebuild skips (switches didn't move).
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: context.read<AppPreferences>().changes,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
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

  // Rebuilt on every preference change: this section is a const widget,
  // which the page's own rebuild skips (switches didn't move).
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: context.read<AppPreferences>().changes,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
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

  // Rebuilt on every preference change: this section is a const widget,
  // which the page's own rebuild skips (switches didn't move).
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: context.read<AppPreferences>().changes,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
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
          value: prefs.sendSound,
          onChanged: (v) => prefs.sendSound = v,
          title: const Text('Send sound'),
          subtitle: const Text('A soft sound when a message goes out (never on silent)'),
        ),
        SwitchListTile(
          value: prefs.autoplayVideos,
          onChanged: (v) => prefs.autoplayVideos = v,
          title: const Text('Autoplay videos in chats'),
          subtitle: const Text('Downloaded videos play muted when you stop scrolling on them'),
        ),
        ListTile(
          title: const Text('Video quality'),
          subtitle: const Text('What videos download and play in. Low saves data; Telegram keeps smaller copies'),
          trailing: DropdownButton<VideoQuality>(
            value: prefs.videoQuality,
            underline: const SizedBox.shrink(),
            onChanged: (v) {
              if (v != null) prefs.videoQuality = v;
            },
            items: const [
              DropdownMenuItem(value: VideoQuality.low, child: Text('Low')),
              DropdownMenuItem(value: VideoQuality.auto, child: Text('Auto')),
              DropdownMenuItem(value: VideoQuality.original, child: Text('Original')),
            ],
          ),
        ),
      ],
    );
  }
}
