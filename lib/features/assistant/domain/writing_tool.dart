/// On-device writing help in the composer (SmolLM2).
enum WritingTool {
  rewrite('Rewrite', 'Clearer sentences and structure, same tone'),
  grammar('Fix grammar', 'Spelling, grammar and punctuation only'),
  summarize('Summarise', 'One or two sentences'),
  friendly('Friendly', 'Warm and casual'),
  formal('Formal', 'Polite and professional'),
  concise('Concise', 'Shorter, same meaning'),
  playful('Playful', 'Light and fun');

  const WritingTool(this.label, this.description);

  final String label;
  final String description;

  bool get isTone => index >= WritingTool.friendly.index;

  /// The instruction for this tool; the message follows as the user turn.
  String get instruction => switch (this) {
    rewrite =>
      'Rewrite the message so it reads better: clearer sentences and a better structure. '
          'Keep the same meaning, tone, language and length. Do not add new information.',
    grammar =>
      'Correct the spelling, grammar and punctuation of the message. Change nothing else: '
          'keep the wording, tone and language.',
    summarize => 'Summarise the message in one or two short sentences, in the same language.',
    friendly => 'Rewrite the message in a warm, friendly, casual tone. Keep the meaning and language.',
    formal => 'Rewrite the message in a polite, formal, professional tone. Keep the meaning and language.',
    concise => 'Rewrite the message to be as short as possible while keeping its meaning and language.',
    playful => 'Rewrite the message in a light, playful tone. Keep the meaning and language.',
  };
}

/// The system prompt for [tool].
String writingSystemPrompt(WritingTool tool) =>
    'You are a writing assistant. You never answer or reply to the message; you only transform the text '
    'between « and ». ${tool.instruction} Reply with only the new text: no quotes, no explanations.';

/// The verb that opens the request for [tool].
String _ask(WritingTool tool) => switch (tool) {
  WritingTool.rewrite => 'Rewrite this message',
  WritingTool.grammar => 'Fix the grammar and spelling of this message',
  WritingTool.summarize => 'Summarise this message',
  WritingTool.friendly => 'Rewrite this message in a friendly tone',
  WritingTool.formal => 'Rewrite this message in a formal tone',
  WritingTool.concise => 'Make this message shorter',
  WritingTool.playful => 'Rewrite this message in a playful tone',
};

/// Two worked examples per tool: small models copy a pattern far more
/// reliably than they follow an instruction (without them the model
/// *replied* to "Hello how are you today" instead of rewriting it).
const _examples = <WritingTool, List<(String, String)>>{
  WritingTool.rewrite: [
    ('hey can u send me the file i need it', 'Hey, could you send me the file? I need it.'),
    ('How are you doing today', 'How are you doing today?'),
  ],
  WritingTool.grammar: [
    ('i has went to the shop yesterday', 'I went to the shop yesterday.'),
    ('how are you doing today', 'How are you doing today?'),
  ],
  WritingTool.summarize: [
    (
      'Hi all, the meeting moved from Monday to Tuesday at 3pm because the room was booked, please update calendars.',
      'The meeting moved to Tuesday at 3pm.',
    ),
    (
      'Are you free tonight? I was thinking we could grab dinner at the new place.',
      'Asking to have dinner tonight.',
    ),
  ],
  WritingTool.friendly: [
    ('Send me the report.', 'Hey! Could you send me the report when you get a chance? Thanks!'),
    ('How are you today', 'Hey, how are you doing today?'),
  ],
  WritingTool.formal: [
    ('hey send me the report', 'Hello, could you please send me the report?'),
    ('How are you today', 'Good day, I hope you are well today.'),
  ],
  WritingTool.concise: [
    (
      'I just wanted to let you know that I will probably be a little bit late today',
      "I'll be a bit late today.",
    ),
    ('How are you doing today, my friend?', 'How are you today?'),
  ],
  WritingTool.playful: [
    ('I will be late', "Running a little behind, save me a seat! 😄"),
    ('How are you today', "Hey you! How's your day going? 😊"),
  ],
};

/// The chat turns for [tool] on [text]: system prompt, examples, then the
/// request with the text in «» so it reads as material, not a message.
List<(String role, String text)> writingTurns(WritingTool tool, String text) => [
  ('system', writingSystemPrompt(tool)),
  for (final (input, output) in _examples[tool]!) ...[
    ('user', '${_ask(tool)}: «$input»'),
    ('assistant', output),
  ],
  ('user', '${_ask(tool)}: «$text»'),
];

/// Strips what small models add around the answer: a preface ("Here is…:"),
/// wrapping quotes, trailing whitespace.
String cleanWritingOutput(String raw) {
  var s = raw.trim();
  final preface = RegExp(
    r'^(sure[,!.]?\s*)?(here(\s+is|\x27s)|the (rewritten|corrected|summari[sz]ed) (message|text))[^:\n]*:\s*',
    caseSensitive: false,
  );
  s = s.replaceFirst(preface, '').trim();
  const pairs = {'«': '»', '"': '"', '“': '”', "'": "'"};
  for (final e in pairs.entries) {
    if (s.length > 1 && s.startsWith(e.key) && s.endsWith(e.value)) {
      s = s.substring(1, s.length - 1).trim();
    }
  }
  return s;
}
