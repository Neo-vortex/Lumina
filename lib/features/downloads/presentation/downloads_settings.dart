import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/storage/app_preferences.dart';
import '../../../core/theme/glow_colors.dart';
import '../../settings/presentation/widgets/settings_section.dart';
import '../bloc/downloads_cubit.dart';
import 'downloads_screen.dart';

/// Settings → Data & storage → Downloads.
class DownloadsSettings extends StatelessWidget {
  const DownloadsSettings({super.key, required this.openMessage});

  final OpenMessage openMessage;

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<AppPreferences>();
    return BlocBuilder<DownloadsCubit, DownloadsState>(
      builder: (context, state) => ListenableBuilder(
        listenable: prefs.changes,
        builder: (context, _) => SettingsSection(
          title: 'Downloads',
          children: [
            ListTile(
              leading: const Icon(Icons.download_rounded, color: GlowColors.cyan),
              title: const Text('Downloads'),
              subtitle: Text('${state.active.length} active · ${state.completed.length} finished'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(DownloadsScreen.route(openMessage: openMessage)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.wifi_rounded, color: GlowColors.violet),
              activeThumbColor: GlowColors.cyan,
              title: const Text('New downloads: Wi-Fi only'),
              subtitle: const Text('They wait for Wi-Fi and resume on their own'),
              value: prefs.downloadsWifiOnlyDefault,
              onChanged: (v) => prefs.downloadsWifiOnlyDefault = v,
            ),
          ],
        ),
      ),
    );
  }
}
