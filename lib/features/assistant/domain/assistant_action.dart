import 'date_resolver.dart';

enum ActionKind { none, calendar, alarm, reminder, note }

/// What the assistant proposes for a message; every field is editable in
/// the confirmation sheet before anything runs.
class ActionDraft {
  ActionDraft({
    required this.kind,
    required this.title,
    this.when,
    this.duration = const Duration(hours: 1),
    this.location = '',
    this.notes = '',
    this.relative,
  });

  ActionKind kind;
  String title;

  /// Start (calendar, reminder) or ring time (alarm).
  DateTime? when;
  Duration duration;
  String location;
  String notes;

  /// Set for "in 20 minutes" reminders (become a timer).
  Duration? relative;

  /// Builds a draft from the model's JSON, with dates resolved from the
  /// message text first (see [DateResolver]).
  static ActionDraft fromModel(
    Map<String, dynamic> json, {
    required String messageText,
    required DateTime now,
  }) {
    final kind = ActionKind.values.firstWhere((k) => k.name == json['action'], orElse: () => ActionKind.none);
    final textHint = DateResolver.fromText(messageText, now);
    final hint = DateResolver.merge(
      textHint,
      DateResolver.fromModel(json['date'] as String?, json['time'] as String?),
    );
    final minutes = (json['duration_minutes'] as num?)?.toInt() ?? 0;
    var title = (json['title'] as String? ?? '').trim();
    if (title.isEmpty) title = _fallbackTitle(messageText);
    return ActionDraft(
      kind: kind,
      title: title,
      when: hint.resolve(now),
      duration: minutes > 0 ? Duration(minutes: minutes) : const Duration(hours: 1),
      location: (json['location'] as String? ?? '').trim(),
      notes: (json['notes'] as String? ?? '').trim(),
      relative: textHint.relative,
    );
  }

  static String _fallbackTitle(String text) {
    final firstLine = text.trim().split('\n').first;
    return firstLine.length > 60 ? '${firstLine.substring(0, 57)}…' : firstLine;
  }
}
