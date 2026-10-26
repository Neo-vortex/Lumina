import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/assistant/domain/writing_tool.dart';

void main() {
  test('rewrite keeps tone; grammar changes nothing else; the reply is text only', () {
    expect(writingSystemPrompt(WritingTool.rewrite), contains('same meaning, tone'));
    expect(writingSystemPrompt(WritingTool.grammar), contains('Change nothing else'));
    for (final t in WritingTool.values) {
      expect(writingSystemPrompt(t), contains('only the new text'));
    }
    expect(WritingTool.formal.isTone, isTrue);
    expect(WritingTool.summarize.isTone, isFalse);
  });

  test('cleanup strips prefaces and wrapping quotes', () {
    expect(cleanWritingOutput('Here is the rewritten message: "See you at 8."'), 'See you at 8.');
    expect(
      cleanWritingOutput('Sure! Here\'s a friendlier version:\nHey, see you at 8!'),
      'Hey, see you at 8!',
    );
    expect(cleanWritingOutput('“Meet at noon.”  '), 'Meet at noon.');
    expect(cleanWritingOutput('Plain answer.'), 'Plain answer.');
  });

  test('the text goes in delimiters after an instruction, with examples first, so the model edits it instead of replying', () {
    final turns = writingTurns(WritingTool.rewrite, 'Hello how are you today');
    final last = turns.last;
    expect(last.$1, 'user');
    expect(last.$2, contains('«Hello how are you today»'));
    expect(last.$2, startsWith('Rewrite'));
    // Few-shot: at least one example pair before the real request.
    expect(turns.where((t) => t.$1 == 'assistant'), isNotEmpty);
    expect(turns.first.$1, 'system');
  });

  test('echoed delimiters are stripped', () {
    expect(cleanWritingOutput('«Hello, how are you today?»'), 'Hello, how are you today?');
  });
}
