import 'assistant_action.dart';
import 'date_resolver.dart';

/// Deterministic guardrails around the tiny model's label.
///
/// Measured on the evaluation set (test/integration/llm_eval_test.dart), a
/// 360M model alone confuses appointments with alarms and misses obvious
/// "save this" notes. Unambiguous phrases settle those cases; the model
/// decides everything else.
abstract final class ActionGuardrails {
  static final _alarm = RegExp(
    r"\b(wake (me )?up|wake me|set (an |the )?alarm|alarm (for|at)|my alarm)\b",
    caseSensitive: false,
  );
  static final _reminder = RegExp(
    r"\b(remind me|reminder|don'?t forget|do not forget|remember to|make sure (you|to))\b",
    caseSensitive: false,
  );
  static final _note = RegExp(
    r'\b(password|passcode|pin( code)?|wi-?fi|door code|code is|address|iban|account (number|no)|'
    r'license|licence|serial|booking (ref|reference|number)|confirmation (code|number)|'
    r'\w+ list\s*:|list\s*:)',
    caseSensitive: false,
  );
  static final _event = RegExp(
    r'\b(meeting|meet|appointment|dentist|doctor|interview|lunch|dinner|breakfast|party|concert|flight|'
    r'departs|wedding|birthday|call at|webinar|class|lecture|exam|match|game|movie|trip)\b',
    caseSensitive: false,
  );

  /// Final action for [text], given the model's [modelLabel].
  static ActionKind decide(ActionKind modelLabel, String text, DateTime now) {
    if (_alarm.hasMatch(text)) return ActionKind.alarm;
    if (_reminder.hasMatch(text)) return ActionKind.reminder;
    if (_note.hasMatch(text) && !_event.hasMatch(text)) return ActionKind.note;
    final when = DateResolver.fromText(text, now);
    final hasWhen = when.date != null || when.hasTime;
    if (_event.hasMatch(text) && hasWhen) return ActionKind.calendar;
    // A concrete day/time is never "nothing to do".
    if (modelLabel == ActionKind.none && hasWhen) return ActionKind.calendar;
    // An alarm needs a clock time; without one the model meant an event.
    if (modelLabel == ActionKind.alarm && !when.hasTime) {
      return when.date != null ? ActionKind.calendar : ActionKind.none;
    }
    return modelLabel;
  }
}
