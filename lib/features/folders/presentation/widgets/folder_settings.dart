import 'package:flutter/material.dart';

import '../../../../core/platform/system_channel.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../settings/presentation/widgets/settings_section.dart';
import '../screens/folder_manager_screen.dart';

/// Settings → Chats → Folders.
class FolderSettings extends StatelessWidget {
  const FolderSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'Folders',
      children: [
        ListTile(
          leading: const Icon(Icons.folder_copy_rounded, color: GlowColors.cyan),
          title: const Text('Chat folders'),
          subtitle: const Text('Create, reorder and share folders'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(FolderManagerScreen.route()),
        ),
        ListTile(
          leading: const Icon(Icons.open_in_new_rounded),
          title: const Text('Open Telegram links in Lumina'),
          subtitle: const Text(
            'tg:// links already open here. For t.me folder and proxy links from other apps, '
            'turn on Lumina under "Open by default".',
          ),
          onTap: () => const SystemChannel().openLinkSettings(),
        ),
      ],
    );
  }
}
