import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/app_preferences.dart';
import '../settings_category.dart';

/// One settings page: the sections filed under [category].
class SettingsCategoryScreen extends StatelessWidget {
  const SettingsCategoryScreen({super.key, required this.category, required this.entries});

  final SettingsCategory category;
  final List<SettingsEntry> entries;

  static Route<void> route(SettingsCategory category, List<SettingsEntry> entries) => MaterialPageRoute(
    builder: (_) => SettingsCategoryScreen(category: category, entries: entries),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(category.title)),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: context.read<AppPreferences>().changes,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [for (final e in entries) e.build(context)],
          ),
        ),
      ),
    );
  }
}
