import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/assistant/domain/reaction_suggestion.dart';

void main() {
  test('model labels map to Telegram reaction emoji; anything else is ignored', () {
    expect(reactionFromModel('{"reaction":"laugh"}'), '🤣');
    expect(reactionFromModel('{"reaction": "broken_heart"}'), '💔');
    expect(reactionFromModel('{"reaction":"heart"}'), '❤');
    expect(reactionFromModel('{"reaction":"angry"}'), isNull);
    expect(reactionFromModel('nonsense'), isNull);
  });
}
