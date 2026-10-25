import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:lumina/features/media/presentation/widgets/attach_sheet.dart';
import 'package:lumina/features/media/presentation/widgets/poll_composer.dart';

void main() {
  group('attach hub tile order', () {
    test('a fresh install keeps the declared order', () {
      expect(attachTileOrder(const {}), ['file', 'location', 'contact', 'poll', 'music', 'roundVideo']);
    });

    test('most used first, ties keep the declared order', () {
      expect(attachTileOrder(const {'music': 3, 'poll': 1, 'contact': 1}), [
        'music',
        'contact',
        'poll',
        'file',
        'location',
        'roundVideo',
      ]);
    });

    test('hidden tiles are left out', () {
      final order = attachTileOrder(
        const {'poll': 9},
        allowPoll: false,
        allowVideoNote: false,
        allowContact: false,
      );
      expect(order, ['file', 'location', 'music']);
    });
  });

  group('buildPoll', () {
    test('incomplete polls are null', () {
      expect(buildPoll(question: ' ', rows: ['a', 'b']), isNull);
      expect(buildPoll(question: 'Q', rows: ['a', '  ']), isNull);
      expect(buildPoll(question: 'Q', rows: ['a', 'b'], quiz: true), isNull);
    });

    test('trims and drops empty rows', () {
      final poll = buildPoll(question: ' Lunch? ', rows: [' pizza ', '', 'sushi', ''])!;
      expect(poll.question.text, 'Lunch?');
      expect(poll.options.map((o) => o.text.text), ['pizza', 'sushi']);
      expect(poll.type, isA<td.InputPollTypeRegular>());
      expect(poll.isAnonymous, isTrue);
    });

    test('quiz maps the correct row past empty rows', () {
      final poll = buildPoll(
        question: 'Capital of France?',
        rows: ['Berlin', '', 'Paris', ''],
        quiz: true,
        correctRow: 2,
        explanation: ' It is Paris ',
      )!;
      final type = poll.type as td.InputPollTypeQuiz;
      expect(type.correctOptionIds, [1]);
      expect(type.explanation.text, 'It is Paris');
    });

    test('a quiz whose correct row was cleared is incomplete', () {
      expect(buildPoll(question: 'Q', rows: ['a', '', 'b'], quiz: true, correctRow: 1), isNull);
      expect(buildPoll(question: 'Q', rows: ['a', 'b'], quiz: true, correctRow: 5), isNull);
    });

    test('regular polls let voters change their vote; quizzes don\'t', () {
      expect(buildPoll(question: 'Q', rows: ['a', 'b'])!.allowsRevoting, isTrue);
      expect(buildPoll(question: 'Q', rows: ['a', 'b'], quiz: true, correctRow: 0)!.allowsRevoting, isFalse);
    });

    test('multiple answers only for regular polls', () {
      final poll = buildPoll(question: 'Q', rows: ['a', 'b'], multiple: true, anonymous: false)!;
      expect(poll.type, isA<td.InputPollTypeRegular>());
      expect(poll.allowsMultipleAnswers, isTrue);
      expect(poll.isAnonymous, isFalse);
    });
  });
}
