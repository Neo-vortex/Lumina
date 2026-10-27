import 'package:flutter/material.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/link_opener.dart';
import '../../../core/theme/glow_colors.dart';

/// The bot part of a bot's profile: what it is, what it says, its commands
/// and its privacy policy.
class BotProfileSection extends StatelessWidget {
  const BotProfileSection({super.key, required this.info});

  final td.BotInfo info;

  @override
  Widget build(BuildContext context) {
    final about = info.shortDescription;
    final description = info.description;
    return Material(
      color: GlowColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: GlowColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (about.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.smart_toy_rounded, color: GlowColors.violet),
              title: Text(about),
              subtitle: const Text('About', style: TextStyle(color: GlowColors.textMuted, fontSize: 12)),
            ),
          if (description.isNotEmpty && description != about)
            ListTile(
              leading: const Icon(Icons.notes_rounded, color: GlowColors.cyan),
              title: Text(description),
            ),
          if (info.commands.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Commands',
                style: TextStyle(color: GlowColors.violet, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            for (final c in info.commands)
              ListTile(
                dense: true,
                title: Text(
                  '/${c.command}',
                  style: const TextStyle(color: GlowColors.cyan, fontWeight: FontWeight.w600),
                ),
                subtitle: c.description.isEmpty ? null : Text(c.description),
              ),
          ],
          if (info.privacyPolicyUrl.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.privacy_tip_rounded, color: GlowColors.cyan),
              title: const Text('Privacy policy'),
              trailing: const Icon(Icons.north_east_rounded, size: 18, color: GlowColors.textMuted),
              onTap: () => openLink(context, info.privacyPolicyUrl),
            ),
        ],
      ),
    );
  }
}
