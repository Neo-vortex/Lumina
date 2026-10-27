import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/glow_colors.dart';
import '../../settings/presentation/widgets/settings_section.dart';
import '../data/auto_download_service.dart';
import '../domain/auto_download_policy.dart';
import 'auto_download_screen.dart';

/// Settings → Data & storage: the entry to [AutoDownloadScreen], with each
/// network's preset at a glance.
class AutoDownloadSettings extends StatelessWidget {
  const AutoDownloadSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.read<AutoDownloadService>();
    return ListenableBuilder(
      listenable: service.changes,
      builder: (context, _) => SettingsSection(
        title: 'Auto-download',
        children: [
          ListTile(
            leading: const Icon(Icons.download_for_offline_rounded, color: GlowColors.cyan),
            title: const Text('Auto-download media'),
            subtitle: Text(
              [for (final n in NetworkKind.values) '${n.label}: ${service.policy(n).preset.label}']
                  .join(' · '),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(AutoDownloadScreen.route()),
          ),
        ],
      ),
    );
  }
}
