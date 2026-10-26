/// The reactions the on-device model may suggest when you tap a message,
/// as Telegram's standard reaction emoji (its laugh is 🤣; 😂 isn't one).
const reactionLabels = <String, String>{
  'happy': '😁',
  'sad': '😢',
  'heart': '❤',
  'laugh': '🤣',
  'broken_heart': '💔',
  'like': '👍',
};

/// JSON schema constraining the model to one of [reactionLabels].
const reactionSchema = {
  'type': 'object',
  'properties': {
    'reaction': {
      'type': 'string',
      'enum': ['happy', 'sad', 'heart', 'laugh', 'broken_heart', 'like'],
    },
  },
  'required': ['reaction'],
};

const reactionSystemPrompt =
    'You pick the one reaction that best fits how someone would react to a chat message. '
    'happy: good news or excitement. sad: bad news or disappointment. heart: love, affection or gratitude. '
    'laugh: a joke or something funny. broken_heart: heartbreak, loss or rejection. like: agreement, '
    'plans or neutral information. Answer only with JSON.';

/// The emoji for the model's answer, or null when it isn't one of ours.
String? reactionFromModel(String raw) {
  final m = RegExp(r'"reaction"\s*:\s*"([a-z_]+)"').firstMatch(raw);
  return m == null ? null : reactionLabels[m.group(1)];
}
