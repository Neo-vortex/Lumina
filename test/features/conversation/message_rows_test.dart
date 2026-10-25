import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/conversation/presentation/widgets/message_rows.dart';

import '../../helpers/fakes.dart';

void main() {
  // 2025-10-25 12:00 UTC-ish; consecutive seconds.
  const t0 = 1761393600;

  test('rows are newest first with a day header above the oldest message', () {
    final rows = buildRows([
      fakeMessage(3, date: t0 + 20),
      fakeMessage(2, date: t0 + 10),
      fakeMessage(1, date: t0),
    ]);
    expect(rows.last, isA<DayHeaderRow>());
    expect((rows.first as BubbleRow).id, 3);
  });

  test('consecutive messages from one sender within 60 s form a run', () {
    final rows = buildRows([
      fakeMessage(3, date: t0 + 20),
      fakeMessage(2, date: t0 + 10),
      fakeMessage(1, date: t0),
    ]).whereType<BubbleRow>().toList();
    // newest first: 3 is last in run, 1 is first in run.
    expect(rows[0].lastInRun, isTrue);
    expect(rows[0].firstInRun, isFalse);
    expect(rows[2].firstInRun, isTrue);
    expect(rows[2].lastInRun, isFalse);
  });

  test('a different sender or a long gap starts a new run', () {
    final rows = buildRows([
      fakeMessage(3, date: t0 + 500),
      fakeMessage(2, date: t0 + 10, senderUserId: 8),
      fakeMessage(1, date: t0),
    ]).whereType<BubbleRow>().toList();
    expect(rows.every((r) => r.firstInRun && r.lastInRun), isTrue);
  });

  test('album parts collapse into one bubble, oldest first', () {
    final rows = buildRows([
      fakeMessage(3, date: t0, albumId: 77),
      fakeMessage(2, date: t0, albumId: 77),
      fakeMessage(1, date: t0 - 100),
    ]).whereType<BubbleRow>().toList();
    expect(rows, hasLength(2));
    expect(rows.first.isAlbum, isTrue);
    expect(rows.first.messages.map((m) => m.id), [2, 3]);
  });

  test('unread divider sits just below the first unread message', () {
    final rows = buildRows([
      fakeMessage(3, date: t0 + 20),
      fakeMessage(2, date: t0 + 10),
      fakeMessage(1, date: t0),
    ], firstUnreadId: 2);
    final dividerIndex = rows.indexWhere((r) => r is UnreadDividerRow);
    expect(dividerIndex, greaterThan(0));
    expect((rows[dividerIndex - 1] as BubbleRow).id, 2);
  });
}
