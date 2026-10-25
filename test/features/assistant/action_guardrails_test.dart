import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/assistant/domain/action_guardrails.dart';
import 'package:lumina/features/assistant/domain/assistant_action.dart';

void main() {
  final now = DateTime(2026, 10, 25, 14);
  ActionKind d(ActionKind model, String text) => ActionGuardrails.decide(model, text, now);

  test('unambiguous phrases win over a wrong model label', () {
    expect(d(ActionKind.calendar, 'set an alarm for 5:45 please'), ActionKind.alarm);
    expect(d(ActionKind.none, 'Pick up the kids at 4 today, dont forget!'), ActionKind.reminder);
    expect(d(ActionKind.none, 'The wifi password is Sunflower-42'), ActionKind.note);
    expect(d(ActionKind.alarm, 'Dentist appointment on Tuesday at 3pm'), ActionKind.calendar);
    expect(d(ActionKind.alarm, 'Flight LH 404 departs Nov 3 at 07:10'), ActionKind.calendar);
  });

  test('the model decides the ambiguous rest', () {
    expect(d(ActionKind.none, 'haha that was so funny'), ActionKind.none);
    expect(d(ActionKind.calendar, 'what do you think about the new phone?'), ActionKind.calendar);
    expect(d(ActionKind.note, 'bring the blue folder'), ActionKind.note);
  });

  test('a concrete time is never "none"; alarms need a clock time', () {
    expect(d(ActionKind.none, 'see you friday at 6'), ActionKind.calendar);
    expect(d(ActionKind.alarm, 'tomorrow'), ActionKind.calendar);
    expect(d(ActionKind.alarm, 'yes'), ActionKind.none);
  });
}
