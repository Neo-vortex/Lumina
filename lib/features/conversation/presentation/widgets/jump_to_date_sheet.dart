import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_sheet.dart';

/// One day of a chat's history: how many messages, and the first one (where a
/// jump lands).
typedef DayCount = ({int count, int firstMessageId});

/// Loads a chat's history page by page (newest first), yielding the per-day
/// counts so far and how many messages were read. Stops at [cap] messages.
typedef DayCountLoader = Stream<({Map<DateTime, DayCount> days, int loaded, bool done})> Function();

/// Counts messages per local day, oldest message of the day kept as the jump target.
Stream<({Map<DateTime, DayCount> days, int loaded, bool done})> countDays(
  Future<List<td.Message>> Function(int fromMessageId) page, {
  int cap = 5000,
}) async* {
  final days = <DateTime, DayCount>{};
  var from = 0, loaded = 0;
  while (loaded < cap) {
    // getChatHistory includes the message it starts from: skip it after the first page.
    final batch = [
      for (final m in await page(from))
        if (from == 0 || m.id != from) m,
    ];
    if (batch.isEmpty) break;
    for (final m in batch) {
      final t = DateTime.fromMillisecondsSinceEpoch(m.date * 1000);
      final day = DateTime(t.year, t.month, t.day);
      final prev = days[day];
      // Pages come newest first, so each later id seen for a day is older.
      days[day] = (count: (prev?.count ?? 0) + 1, firstMessageId: m.id);
    }
    loaded += batch.length;
    final next = batch.last.id;
    if (next == from) break;
    from = next;
    yield (days: Map.of(days), loaded: loaded, done: false);
  }
  yield (days: days, loaded: loaded, done: true);
}

/// Opens the calendar on [initial] (the tapped date header) and returns the
/// message to jump to, or null.
Future<int?> showJumpToDateSheet(
  BuildContext context, {
  required DateTime initial,
  required DayCountLoader load,
}) => showGlowSheet<int>(
  context,
  title: 'Jump to date',
  builder: (_) => JumpToDateSheet(initial: initial, load: load),
);

class JumpToDateSheet extends StatefulWidget {
  const JumpToDateSheet({super.key, required this.initial, required this.load});

  final DateTime initial;
  final DayCountLoader load;

  @override
  State<JumpToDateSheet> createState() => _JumpToDateSheetState();
}

class _JumpToDateSheetState extends State<JumpToDateSheet> {
  late DateTime _month = DateTime(widget.initial.year, widget.initial.month);
  late DateTime _selected = DateTime(widget.initial.year, widget.initial.month, widget.initial.day);
  Map<DateTime, DayCount> _days = const {};
  var _loaded = 0;
  var _done = false;
  StreamSubscription<({Map<DateTime, DayCount> days, int loaded, bool done})>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.load().listen(
      (s) => setState(() {
        _days = s.days;
        _loaded = s.loaded;
        _done = s.done;
      }),
      onError: (Object _) => setState(() => _done = true),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  int _count(DateTime d) => _days[d]?.count ?? 0;

  /// The nearest days with messages before and after [d].
  (DateTime?, DateTime?) _neighbours(DateTime d) {
    DateTime? before, after;
    for (final day in _days.keys) {
      if (day.isBefore(d) && (before == null || day.isAfter(before))) before = day;
      if (day.isAfter(d) && (after == null || day.isBefore(after))) after = day;
    }
    return (before, after);
  }

  void _jump(DateTime day) {
    final target = _days[day];
    if (target == null) return;
    HapticFeedback.selectionClick();
    Navigator.pop(context, target.firstMessageId);
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static String _short(DateTime d) => '${_months[d.month - 1].substring(0, 3)} ${d.day}';

  @override
  Widget build(BuildContext context) {
    final first = DateTime(_month.year, _month.month);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = (first.weekday + 6) % 7; // Monday first
    final today = DateTime.now();
    final selectedCount = _count(_selected);
    final (before, after) = _neighbours(_selected);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Brief progress while the history is counted.
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _done
                ? const SizedBox(height: 2)
                : Column(
                    children: [
                      const LinearProgressIndicator(minHeight: 2, color: GlowColors.cyan),
                      const SizedBox(height: 4),
                      Text(
                        'Counting messages… $_loaded',
                        style: const TextStyle(fontSize: 11, color: GlowColors.textMuted),
                      ),
                    ],
                  ),
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
              ),
              Expanded(
                child: Text(
                  '${_months[_month.month - 1]} ${_month.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: DateTime(_month.year, _month.month + 1).isAfter(today)
                    ? null
                    : () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
              ),
            ],
          ),
          Row(
            children: [
              for (final w in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Text(
                    w,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: GlowColors.textMuted, fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.95,
            children: [
              for (var i = 0; i < lead; i++) const SizedBox.shrink(),
              for (var d = 1; d <= daysInMonth; d++)
                _DayCell(
                  day: d,
                  count: _count(DateTime(_month.year, _month.month, d)),
                  selected: DateTime(_month.year, _month.month, d) == _selected,
                  counting: !_done,
                  onTap: () {
                    final day = DateTime(_month.year, _month.month, d);
                    if (_count(day) > 0) {
                      setState(() => _selected = day);
                      _jump(day);
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_done && selectedCount == 0) ...[
            Text(
              _days.isEmpty ? 'No messages in this chat yet.' : 'No messages on ${_short(_selected)}.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: GlowColors.textMuted),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (before != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _jump(before),
                      icon: const Icon(Icons.west_rounded, size: 18),
                      label: Text('${_short(before)} (${_count(before)})'),
                    ),
                  ),
                if (before != null && after != null) const SizedBox(width: 8),
                if (after != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _jump(after),
                      icon: const Icon(Icons.east_rounded, size: 18),
                      label: Text('${_short(after)} (${_count(after)})'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.count,
    required this.selected,
    required this.counting,
    required this.onTap,
  });

  final int day;
  final int count;
  final bool selected;
  final bool counting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0;
    return Semantics(
      button: enabled,
      enabled: enabled,
      label: '$day, ${enabled ? '$count messages' : 'no messages'}',
      excludeSemantics: true,
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: 22,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected && enabled ? GlowColors.violet.withValues(alpha: 0.35) : null,
            border: selected ? Border.all(color: GlowColors.cyan, width: 1.5) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: TextStyle(
                  fontWeight: enabled ? FontWeight.w700 : FontWeight.w400,
                  color: enabled
                      ? GlowColors.text
                      : GlowColors.textMuted.withValues(alpha: counting ? 0.6 : 0.35),
                ),
              ),
              if (enabled)
                Text(
                  count > 999 ? '999+' : '$count',
                  style: const TextStyle(fontSize: 9, color: GlowColors.cyan, height: 1.1),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
