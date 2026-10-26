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
    'You are a writing assistant. ${tool.instruction} '
    'Reply with only the new message text: no quotes, no explanations, no preface.';

/// Strips what small models add around the answer: a preface ("Here is…:"),
/// wrapping quotes, trailing whitespace.
String cleanWritingOutput(String raw) {
  var s = raw.trim();
  final preface = RegExp(
    r'^(sure[,!.]?\s*)?(here(\s+is|\x27s)|the (rewritten|corrected|summari[sz]ed) (message|text))[^:\n]*:\s*',
    caseSensitive: false,
  );
  s = s.replaceFirst(preface, '').trim();
  const pairs = {'"': '"', '“': '”', "'": "'", '«': '»'};
  for (final e in pairs.entries) {
    if (s.length > 1 && s.startsWith(e.key) && s.endsWith(e.value)) {
      s = s.substring(1, s.length - 1).trim();
    }
  }
  return s;
}
