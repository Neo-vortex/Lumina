import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/assistant/domain/assistant_action.dart';

void main() {
  final now = DateTime(2026, 10, 25, 14);

  test('message text dates override a wrong model date', () {
    final d = ActionDraft.fromModel(
      {'action': 'calendar', 'title': 'Team sync', 'date': '2024-01-01', 'time': '', 'duration_minutes': 30},
      messageText: 'Team sync tomorrow at 10:30?',
      now: now,
    );
    expect(d.kind, ActionKind.calendar);
    expect(d.when, DateTime(2026, 10, 26, 10, 30));
    expect(d.duration, const Duration(minutes: 30));
  });

  test('relative reminders keep the offset (become timers)', () {
    final d = ActionDraft.fromModel(
      {'action': 'reminder', 'title': 'Take the pizza out', 'date': '', 'time': ''},
      messageText: 'take the pizza out in 15 minutes',
      now: now,
    );
    expect(d.relative, const Duration(minutes: 15));
    expect(d.when, now.add(const Duration(minutes: 15)));
  });

  test('unknown action and empty title fall back safely', () {
    final d = ActionDraft.fromModel(
      {'action': 'launch rockets', 'title': '', 'date': '', 'time': ''},
      messageText: 'hello there',
      now: now,
    );
    expect(d.kind, ActionKind.none);
    expect(d.title, 'hello there');
  });

  test('the model fills in what the text lacks', () {
    final d = ActionDraft.fromModel(
      {'action': 'alarm', 'title': 'Wake up', 'date': '', 'time': '06:45'},
      messageText: 'wake me up early tomorrow',
      now: now,
    );
    expect(d.when, DateTime(2026, 10, 26, 6, 45));
  });
}
