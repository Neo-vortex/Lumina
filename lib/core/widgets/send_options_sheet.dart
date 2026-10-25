import 'package:flutter/material.dart';

import '../telegram/send_options.dart';
import '../theme/glow_colors.dart';
import 'schedule_picker.dart';

export 'schedule_picker.dart';

/// The long-press-send sheet: silent, scheduled or send-when-online.
/// Null when cancelled.
Future<SendOptions?> showSendOptionsSheet(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: GlowColors.surfaceHigh,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.notifications_off_rounded),
            title: const Text('Send without sound'),
            onTap: () => Navigator.pop(context, 'silent'),
          ),
          ListTile(
            leading: const Icon(Icons.schedule_send_rounded),
            title: const Text('Schedule message'),
            onTap: () => Navigator.pop(context, 'schedule'),
          ),
          ListTile(
            leading: const Icon(Icons.wifi_tethering_rounded),
            title: const Text('Send when online'),
            subtitle: const Text('Delivered as soon as they come online'),
            onTap: () => Navigator.pop(context, 'online'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return null;
  switch (choice) {
    case 'silent':
      return const SendOptions(silent: true);
    case 'online':
      return const SendOptions(whenOnline: true);
    case 'schedule':
      final at = await pickScheduleTime(context);
      return at == null ? null : SendOptions(scheduleAt: at);
  }
  return null;
}
