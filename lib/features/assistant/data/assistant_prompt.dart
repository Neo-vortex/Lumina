import 'package:intl/intl.dart';
import 'package:llamadart/llamadart.dart';

import '../domain/assistant_action.dart';

/// The four phone actions, declared as tools: FunctionGemma is trained to
/// call functions, so "no call" is the natural "nothing to do".
List<ToolDefinition> assistantTools() => [
  ToolDefinition(
    name: 'create_calendar_event',
    description: 'Add a meeting, appointment or event at a specific day/time to the calendar.',
    parameters: [
      ToolParam.string('title', description: 'Short event title', required: true),
      ToolParam.string('date', description: 'YYYY-MM-DD'),
      ToolParam.string('time', description: 'HH:MM, 24-hour'),
      ToolParam.integer('duration_minutes', description: 'Length in minutes'),
      ToolParam.string('location', description: 'Where it happens'),
    ],
  ),
  ToolDefinition(
    name: 'set_alarm',
    description: 'Set an alarm clock to ring at a clock time, e.g. to wake up.',
    parameters: [
      ToolParam.string('time', description: 'HH:MM, 24-hour', required: true),
      ToolParam.string('label', description: 'Alarm label'),
    ],
  ),
  ToolDefinition(
    name: 'set_reminder',
    description: 'Remind the user to do something later (at a time, or in N minutes/hours).',
    parameters: [
      ToolParam.string('task', description: 'What to remember to do', required: true),
      ToolParam.string('date', description: 'YYYY-MM-DD'),
      ToolParam.string('time', description: 'HH:MM, 24-hour'),
    ],
  ),
  ToolDefinition(
    name: 'no_action',
    description:
        'Use when the message is small talk, a reaction, a question, or needs nothing scheduled or saved.',
    parameters: [ToolParam.string('reason', description: 'Why nothing is needed')],
  ),
  ToolDefinition(
    name: 'save_note',
    description: 'Save useful information from the message as a note: passwords, codes, addresses, lists, instructions.',
    parameters: [
      ToolParam.string('title', description: 'Short note title', required: true),
      ToolParam.string('content', description: 'What to save'),
    ],
  ),
];

List<LlamaChatMessage> assistantPrompt(
  String messageText, {
  required String userName,
  required String username,
  required String senderName,
  required DateTime now,
  DateTime? messageTime,
}) {
  final system = [
    'You are a phone assistant. Read the chat message and call exactly one function.',
    'Events, appointments, meetings, lunches or parties at a day or time: create_calendar_event.',
    'Waking up or ringing at a clock time: set_alarm. "Remind me", "don\'t forget", "in N minutes": set_reminder.',
    'Passwords, codes, addresses, numbers or lists worth keeping: save_note. Anything else: no_action.',
    'Never answer with text.',
    'Today is ${DateFormat('EEEE yyyy-MM-dd').format(now)}, the time is ${DateFormat.Hm().format(now)}.',
    'The user is $userName${username.isEmpty ? '' : ' (@$username)'}. The message is from $senderName'
        '${messageTime == null ? '' : ' at ${DateFormat('yyyy-MM-dd HH:mm').format(messageTime)}'}.',
  ].join(' ');
  return [
    LlamaChatMessage.fromText(role: LlamaChatRole.system, text: system),
    LlamaChatMessage.fromText(role: LlamaChatRole.user, text: messageText),
  ];
}

/// Maps the model's function call (if any) to an editable draft.
ActionDraft draftFromToolCalls(
  List<({String name, Map<String, dynamic> arguments})> calls, {
  required String messageText,
  required DateTime now,
}) {
  if (calls.isEmpty) {
    return ActionDraft.fromModel(const {'action': 'none'}, messageText: messageText, now: now);
  }
  final c = calls.first;
  final a = c.arguments;
  String s(String k) => (a[k] ?? '').toString();
  final json = switch (c.name) {
    'create_calendar_event' => {
      'action': 'calendar',
      'title': s('title'),
      'date': s('date'),
      'time': s('time'),
      'duration_minutes': int.tryParse(s('duration_minutes')) ?? 0,
      'location': s('location'),
    },
    'set_alarm' => {
      'action': 'alarm',
      'title': s('label').isEmpty ? 'Alarm' : s('label'),
      'date': '',
      'time': s('time'),
    },
    'set_reminder' => {'action': 'reminder', 'title': s('task'), 'date': s('date'), 'time': s('time')},
    'save_note' => {'action': 'note', 'title': s('title'), 'date': '', 'time': '', 'notes': s('content')},
    _ => {'action': 'none'},
  };
  return ActionDraft.fromModel(json, messageText: messageText, now: now);
}

/// JSON schema for the classification mode. "none" is listed last so the
/// grammar doesn't nudge the model towards it.
const actionSchema = {
  'type': 'object',
  'properties': {
    'action': {
      'type': 'string',
      'enum': ['calendar', 'alarm', 'reminder', 'note', 'none'],
    },
    'title': {'type': 'string'},
    'date': {'type': 'string'},
    'time': {'type': 'string'},
    'duration_minutes': {'type': 'integer'},
    'location': {'type': 'string'},
    'notes': {'type': 'string'},
  },
  'required': ['action', 'title', 'date', 'time'],
};

/// Few-shot classification prompt (JSON mode).
List<LlamaChatMessage> classificationPrompt(
  String messageText, {
  required String userName,
  required String username,
  required String senderName,
  required DateTime now,
  DateTime? messageTime,
}) {
  final today = DateFormat('yyyy-MM-dd').format(now);
  final tomorrow = DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 1)));
  final system = [
    'Classify a chat message into one phone action and fill the fields. Reply with JSON only.',
    'calendar = an event, meeting, appointment, flight or party at a day/time.',
    'alarm = ring at a clock time, e.g. waking up.',
    'reminder = the user must remember to do something ("remind me", "don\'t forget", "in 20 minutes").',
    'note = information worth keeping: passwords, codes, addresses, lists, numbers.',
    'none = small talk, reactions, questions.',
    'Today is ${DateFormat('EEEE').format(now)} $today, time ${DateFormat.Hm().format(now)}. The user is $userName'
        '${username.isEmpty ? '' : ' (@$username)'}; the message is from $senderName.',
    'Examples:',
    'Message: "Meeting with Sam tomorrow 10:00 in room 4" → {"action":"calendar","title":"Meeting with Sam","date":"$tomorrow","time":"10:00","location":"room 4"}',
    'Message: "wake me at 7" → {"action":"alarm","title":"Wake up","date":"","time":"07:00"}',
    'Message: "remind me to buy bread in 1 hour" → {"action":"reminder","title":"Buy bread","date":"","time":""}',
    'Message: "door code 4512, flat 3B" → {"action":"note","title":"Door code","date":"","time":"","notes":"door code 4512, flat 3B"}',
    'Message: "lol nice" → {"action":"none","title":"","date":"","time":""}',
  ].join('\n');
  return [
    LlamaChatMessage.fromText(role: LlamaChatRole.system, text: system),
    LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Message: "$messageText"'),
  ];
}

/// Label-only schema: the model decides *what*; Dart works out *when*.
const labelSchema = {
  'type': 'object',
  'properties': {
    'action': {
      'type': 'string',
      'enum': ['calendar', 'alarm', 'reminder', 'note', 'none'],
    },
    'title': {'type': 'string'},
  },
  'required': ['action', 'title'],
};

/// Few-shot prompt for [labelSchema], two examples per class.
List<LlamaChatMessage> labelPrompt(
  String messageText, {
  required String userName,
  required String senderName,
}) {
  const examples = [
    ('Meeting with Sam tomorrow 10:00 in room 4', 'calendar', 'Meeting with Sam'),
    ('Concert on Saturday at 8pm, Blue Hall', 'calendar', 'Concert'),
    ('wake me at 7', 'alarm', 'Wake up'),
    ('set an alarm for 6:15', 'alarm', 'Alarm'),
    ('remind me to buy bread in 1 hour', 'reminder', 'Buy bread'),
    ("don't forget to water the plants tonight", 'reminder', 'Water the plants'),
    ('door code 4512, flat 3B', 'note', 'Door code'),
    ('Groceries: apples, pasta, coffee', 'note', 'Groceries'),
    ('lol nice', 'none', ''),
    ('how are you doing?', 'none', ''),
  ];
  final system = [
    'You label chat messages for $userName with the phone action they need.',
    'calendar: an event, meeting, appointment, flight or party at a day/time.',
    'alarm: ring at a clock time, e.g. waking up.',
    'reminder: $userName must remember to do something.',
    'note: information worth keeping: passwords, codes, addresses, lists, numbers.',
    'none: small talk, reactions, opinions, questions.',
    'Reply with JSON {"action": ..., "title": short title}.',
  ].join('\n');
  return [
    LlamaChatMessage.fromText(role: LlamaChatRole.system, text: system),
    for (final (text, action, title) in examples) ...[
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: text),
      LlamaChatMessage.fromText(role: LlamaChatRole.assistant, text: '{"action":"$action","title":"$title"}'),
    ],
    LlamaChatMessage.fromText(role: LlamaChatRole.user, text: messageText),
  ];
}
