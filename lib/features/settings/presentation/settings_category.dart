import 'package:flutter/material.dart';

/// The pages under Settings. Each feature's settings section is filed under
/// one of these (see [SettingsEntry]); the top page lists only the categories.
enum SettingsCategory {
  privacy('Privacy', Icons.shield_rounded),
  chats('Chats', Icons.chat_bubble_rounded),
  media('Media & voice', Icons.graphic_eq_rounded),
  notifications('Notifications', Icons.notifications_rounded),
  data('Data & storage', Icons.storage_rounded),
  connection('Connection & calls', Icons.wifi_tethering_rounded);

  const SettingsCategory(this.title, this.icon);

  final String title;
  final IconData icon;
}

/// One settings section and the page it lives on.
class SettingsEntry {
  const SettingsEntry(this.category, this.build, {this.forBots = true});

  final SettingsCategory category;
  final WidgetBuilder build;

  /// False for sections that only apply to user accounts.
  final bool forBots;
}
