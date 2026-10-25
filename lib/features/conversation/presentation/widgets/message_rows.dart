import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/display.dart';

/// One row of the (reversed) conversation list.
sealed class MessageRow {
  const MessageRow();
}

final class DayHeaderRow extends MessageRow {
  const DayHeaderRow(this.day);
  final DateTime day;
}

final class UnreadDividerRow extends MessageRow {
  const UnreadDividerRow();
}

final class ServiceRow extends MessageRow {
  const ServiceRow(this.message);
  final td.Message message;
}

/// A message (or an album of several) with its position in a sender run.
final class BubbleRow extends MessageRow {
  const BubbleRow({required this.messages, required this.firstInRun, required this.lastInRun});

  /// One message, or an album (oldest first).
  final List<td.Message> messages;

  /// First (top) bubble of a run: shows the sender name in groups.
  final bool firstInRun;

  /// Last (bottom) bubble of a run: shows time and the tail radius.
  final bool lastInRun;

  td.Message get primary => messages.last;
  td.Message get first => messages.first;
  int get id => messages.first.id;
  bool get isAlbum => messages.length > 1;
}

/// Messages within this window from one sender form a run (UX-23).
const runWindow = Duration(seconds: 60);

/// Flattens [newestFirst] into rows for a `reverse: true` list, so index 0 is
/// the newest row. Albums (same `mediaAlbumId`) collapse into one bubble.
List<MessageRow> buildRows(List<td.Message> newestFirst, {int? firstUnreadId}) {
  // Work oldest → newest, then reverse.
  final chronological = newestFirst.reversed.toList();
  final groups = <List<td.Message>>[];
  for (final m in chronological) {
    if (m.mediaAlbumId != 0 && groups.isNotEmpty && groups.last.last.mediaAlbumId == m.mediaAlbumId) {
      groups.last.add(m);
    } else {
      groups.add([m]);
    }
  }

  final rows = <MessageRow>[];
  DateTime? lastDay;
  for (var i = 0; i < groups.length; i++) {
    final g = groups[i];
    final m = g.first;
    final date = Display.messageDate(m);
    final day = DateTime(date.year, date.month, date.day);
    if (lastDay != day) {
      rows.add(DayHeaderRow(day));
      lastDay = day;
    }
    if (firstUnreadId != null && g.any((x) => x.id == firstUnreadId)) rows.add(const UnreadDividerRow());
    if (Display.isService(m)) {
      rows.add(ServiceRow(m));
      continue;
    }
    final prev = i > 0 ? groups[i - 1].last : null;
    final next = i < groups.length - 1 ? groups[i + 1].first : null;
    rows.add(BubbleRow(messages: g, firstInRun: !_sameRun(prev, m), lastInRun: !_sameRun(g.last, next)));
  }
  return rows.reversed.toList();
}

bool _sameRun(td.Message? a, td.Message? b) {
  if (a == null || b == null) return false;
  if (Display.isService(a) || Display.isService(b)) return false;
  if (Display.senderId(a.senderId) != Display.senderId(b.senderId) || a.isOutgoing != b.isOutgoing) {
    return false;
  }
  final da = Display.messageDate(a), db = Display.messageDate(b);
  if (da.day != db.day || da.month != db.month || da.year != db.year) return false;
  return db.difference(da).abs() <= runWindow;
}
