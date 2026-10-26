import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_sheet.dart';

/// "Details" from the message menu: ids and exact times. TDLib records the
/// server's send time (also the time an incoming message was sent), the
/// last edit and, for your messages in private chats, when it was read.
Future<void> showMessageDetails(BuildContext context, td.Message m, {Future<String?>? readStatus}) =>
    showGlowSheet<void>(
      context,
      title: 'Message details',
      accent: GlowColors.cyan,
      builder: (context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Row(label: 'Message ID', value: '${m.id}', copy: true),
            _Row(label: 'Chat ID', value: '${m.chatId}', copy: true),
            _Row(
              label: 'Sender ID',
              value: switch (m.senderId) {
                td.MessageSenderUser(:final userId) => '$userId',
                td.MessageSenderChat(:final chatId) => '$chatId',
              },
              copy: true,
            ),
            _Row(label: m.isOutgoing ? 'Sent' : 'Sent (server time)', value: exactTime(m.date)),
            if (m.editDate > 0) _Row(label: 'Edited', value: exactTime(m.editDate)),
            if (m.forwardInfo case final f?) _Row(label: 'Originally sent', value: exactTime(f.date)),
            if (readStatus != null)
              FutureBuilder<String?>(
                future: readStatus,
                builder: (context, snap) =>
                    snap.data == null ? const SizedBox.shrink() : _Row(label: 'Read', value: snap.data!),
              ),
          ],
        ),
      ),
    );

/// 2026-10-26 14:02:37, local time.
String exactTime(int unix) {
  final t = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.copy = false});

  final String label;
  final String value;
  final bool copy;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    title: Text(label, style: const TextStyle(color: GlowColors.textMuted, fontSize: 12)),
    subtitle: Text(value, style: const TextStyle(color: GlowColors.text, fontSize: 15)),
    trailing: copy ? const Icon(Icons.copy_rounded, size: 18, color: GlowColors.textMuted) : null,
    onTap: copy
        ? () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
          }
        : null,
  );
}
