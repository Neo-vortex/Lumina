import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/glow_colors.dart';

/// Picks when a message should go out: quick presets first, then a full
/// date + time picker. Null when cancelled.
Future<DateTime?> pickScheduleTime(BuildContext context, {DateTime? initial, DateTime? now}) async {
  final n = now ?? DateTime.now();
  final presets = schedulePresets(n);
  final choice = await showModalBottomSheet<Object>(
    context: context,
    backgroundColor: GlowColors.surfaceHigh,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Send later', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          for (final (label, at) in presets)
            ListTile(
              leading: const Icon(Icons.schedule_rounded, color: GlowColors.cyan),
              title: Text(label),
              trailing: Text(
                DateFormat(at.day == n.day ? 'HH:mm' : 'EEE HH:mm').format(at),
                style: const TextStyle(color: GlowColors.textMuted),
              ),
              onTap: () => Navigator.pop(context, at),
            ),
          ListTile(
            leading: const Icon(Icons.edit_calendar_rounded, color: GlowColors.violet),
            title: const Text('Pick date & time'),
            onTap: () => Navigator.pop(context, 'custom'),
          ),
        ],
      ),
    ),
  );
  if (choice is DateTime) return choice;
  if (choice != 'custom' || !context.mounted) return null;
  final start = initial ?? n.add(const Duration(hours: 1));
  final date = await showDatePicker(
    context: context,
    firstDate: n,
    lastDate: n.add(const Duration(days: 365)),
    initialDate: start.isBefore(n) ? n : start,
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
  if (time == null) return null;
  final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
  if (!at.isAfter(DateTime.now())) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick a time in the future')));
    }
    return null;
  }
  return at;
}

/// "In 1 hour", "This evening", "Tomorrow morning", "Monday morning".
List<(String, DateTime)> schedulePresets(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final evening = today.add(const Duration(hours: 20));
  final tomorrow9 = today.add(const Duration(days: 1, hours: 9));
  final toMonday = (DateTime.monday - now.weekday + 7) % 7;
  final monday9 = today.add(Duration(days: toMonday == 0 ? 7 : toMonday, hours: 9));
  return [
    ('In 1 hour', DateTime(now.year, now.month, now.day, now.hour + 1, now.minute)),
    if (evening.difference(now) > const Duration(minutes: 90)) ('This evening', evening),
    ('Tomorrow morning', tomorrow9),
    if (monday9.difference(tomorrow9).inDays > 0) ('Monday morning', monday9),
  ];
}
