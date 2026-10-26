import 'package:flutter/material.dart';

import '../../../core/theme/glow_colors.dart';

/// Folder glow colours and icons. Telegram colour ids: 0 red, 1 orange,
/// 2 violet, 3 green, 4 cyan, 5 blue, 6 pink; -1 none.
abstract final class FolderPalette {
  static const choices = <({int colorId, Color color, String label})>[
    (colorId: 4, color: GlowColors.cyan, label: 'Cyan'),
    (colorId: 3, color: GlowColors.teal, label: 'Teal'),
    (colorId: 2, color: GlowColors.violet, label: 'Violet'),
    (colorId: 6, color: GlowColors.magenta, label: 'Magenta'),
    (colorId: 1, color: GlowColors.amber, label: 'Amber'),
    (colorId: 0, color: GlowColors.coral, label: 'Coral'),
  ];

  /// [colorId] when set, else a palette colour picked by [position].
  static Color colorOf(int colorId, {required int position}) => switch (colorId) {
    0 => GlowColors.coral,
    1 => GlowColors.amber,
    2 => GlowColors.violet,
    3 => GlowColors.teal,
    4 || 5 => GlowColors.cyan,
    6 => GlowColors.magenta,
    _ => choices[position % choices.length].color,
  };

  /// Telegram's folder icon names (what other apps show and sync).
  static const iconNames = <String, IconData>{
    'All': Icons.forum_rounded,
    'Unread': Icons.mark_chat_unread_rounded,
    'Unmuted': Icons.notifications_active_rounded,
    'Bots': Icons.smart_toy_rounded,
    'Channels': Icons.campaign_rounded,
    'Groups': Icons.groups_rounded,
    'Private': Icons.person_rounded,
    'Custom': Icons.folder_rounded,
    'Setup': Icons.tune_rounded,
    'Cat': Icons.pets_rounded,
    'Crown': Icons.workspace_premium_rounded,
    'Favorite': Icons.star_rounded,
    'Flower': Icons.local_florist_rounded,
    'Game': Icons.sports_esports_rounded,
    'Home': Icons.home_rounded,
    'Love': Icons.favorite_rounded,
    'Mask': Icons.theater_comedy_rounded,
    'Party': Icons.celebration_rounded,
    'Sport': Icons.sports_soccer_rounded,
    'Study': Icons.school_rounded,
    'Trade': Icons.trending_up_rounded,
    'Travel': Icons.luggage_rounded,
    'Work': Icons.work_rounded,
    'Airplane': Icons.flight_rounded,
    'Book': Icons.menu_book_rounded,
    'Light': Icons.lightbulb_rounded,
    'Like': Icons.thumb_up_rounded,
    'Money': Icons.payments_rounded,
    'Note': Icons.sticky_note_2_rounded,
    'Palette': Icons.palette_rounded,
  };

  static IconData iconOf(String? name) => iconNames[name] ?? Icons.folder_rounded;
}
