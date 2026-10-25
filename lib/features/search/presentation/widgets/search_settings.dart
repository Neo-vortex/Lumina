import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/app_preferences.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../settings/presentation/widgets/settings_section.dart';
import '../../data/message_indexer.dart';

/// Settings → Search: the local full-text index.
class SearchSettings extends StatelessWidget {
  const SearchSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<AppPreferences>();
    final indexer = context.read<MessageIndexer>();
    return ListenableBuilder(
      listenable: Listenable.merge([indexer, prefs.changes]),
      builder: (context, _) => SettingsSection(
        title: 'Search',
        children: [
          SwitchListTile(
            value: prefs.searchIndexEnabled,
            onChanged: (v) {
              prefs.searchIndexEnabled = v;
              if (v) indexer.rebuild().ignore();
            },
            secondary: const Icon(Icons.manage_search_rounded, color: GlowColors.cyan),
            title: const Text('Fast local message search'),
            subtitle: const Text(
              'Encrypted index on this device. Exact matches inside words and in any language, even offline.',
            ),
          ),
          if (prefs.searchIndexEnabled) ...[
            SwitchListTile(
              value: prefs.searchBackfill,
              onChanged: (v) => prefs.searchBackfill = v,
              title: const Text('Include older messages'),
              subtitle: const Text('Indexes chat history in the background'),
            ),
            ListTile(
              title: Text('${indexer.stats.messages} messages in ${indexer.stats.chats} chats'),
              subtitle: Text(indexer.backfilling ? 'Indexing history…' : 'Up to date'),
              trailing: TextButton(onPressed: () => indexer.rebuild().ignore(), child: const Text('Rebuild')),
            ),
          ],
        ],
      ),
    );
  }
}
