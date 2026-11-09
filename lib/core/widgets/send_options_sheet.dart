import 'package:flutter/material.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../telegram/send_options.dart';
import '../theme/glow_colors.dart';
import 'schedule_picker.dart';

export 'schedule_picker.dart';

/// The long-press-send sheet: an effect (when [effects] gives any), silent,
/// scheduled or send-when-online. Null when cancelled.
Future<SendOptions?> showSendOptionsSheet(
  BuildContext context, {
  Future<List<td.MessageEffect>> Function()? effects,
}) async {
  final effectList = effects?.call();
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: GlowColors.surfaceHigh,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (effectList != null)
            FutureBuilder<List<td.MessageEffect>>(
              future: effectList,
              builder: (context, snap) {
                final list = snap.data ?? const <td.MessageEffect>[];
                if (list.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Send with an effect',
                        style: TextStyle(color: GlowColors.textMuted, fontSize: 12.5),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final e in list)
                            InkResponse(
                              radius: 28,
                              onTap: () => Navigator.pop(context, 'effect:${e.id}'),
                              child: Container(
                                width: 52,
                                height: 52,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: GlowColors.surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: GlowColors.outline),
                                ),
                                child: Text(e.emoji, style: const TextStyle(fontSize: 26)),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
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
  if (choice != null && choice.startsWith('effect:')) {
    return SendOptions(effectId: int.parse(choice.substring(7)));
  }
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
