import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/assistant/domain/date_resolver.dart';

void main() {
  // Saturday 25 Oct 2026, 14:00.
  final now = DateTime(2026, 10, 25, 14);

  DateTime? at(String text) => DateResolver.fromText(text, now).resolve(now);

  test('tomorrow at 5 means 17:00 tomorrow', () {
    expect(at('lets meet tomorrow at 5'), DateTime(2026, 10, 26, 17));
  });

  test('explicit am/pm and 24 h times', () {
    expect(at('call me tomorrow 9am'), DateTime(2026, 10, 26, 9));
    expect(at('dinner today 7:30 pm'), DateTime(2026, 10, 25, 19, 30));
    expect(at('standup on 2026-11-03 at 10:15'), DateTime(2026, 11, 3, 10, 15));
  });

  test('weekday names pick the next occurrence', () {
    expect(at('see you on monday at noon'), DateTime(2026, 10, 27 - 1, 12)); // Mon 26 Oct
    expect(at('friday 18:00 drinks'), DateTime(2026, 10, 30, 18));
  });

  test('relative offsets', () {
    expect(at('remind me in 20 minutes'), now.add(const Duration(minutes: 20)));
    expect(at('in 2 hours'), now.add(const Duration(hours: 2)));
    expect(at('in an hour'), now.add(const Duration(hours: 1)));
  });

  test('month names and day/month numbers', () {
    expect(at('birthday party March 3 at 6pm'), DateTime(2027, 3, 3, 18));
    expect(at('meeting 3 November 10:00'), DateTime(2026, 11, 3, 10));
    expect(at('due 15/11'), DateTime(2026, 11, 15, 9));
  });

  test('a bare time already past today rolls to tomorrow', () {
    expect(at('wake me at 7:00'), DateTime(2026, 10, 26, 7));
  });

  test('no date or time', () {
    expect(DateResolver.fromText('buy milk', now).isEmpty, isTrue);
  });

  test('text wins over model fields; model fills gaps', () {
    final merged = DateResolver.merge(
      DateResolver.fromText('tomorrow', now),
      DateResolver.fromModel('2026-12-01', '15:45'),
    );
    expect(merged.resolve(now), DateTime(2026, 10, 26, 15, 45));
    expect(DateResolver.fromModel('2026-02-30', '25:00').isEmpty, isTrue);
  });
}
