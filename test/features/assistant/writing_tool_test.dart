import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/assistant/domain/writing_tool.dart';

void main() {
  test('rewrite keeps tone; grammar changes nothing else; the reply is text only', () {
    expect(writingSystemPrompt(WritingTool.rewrite), contains('same meaning, tone'));
    expect(writingSystemPrompt(WritingTool.grammar), contains('Change nothing else'));
    for (final t in WritingTool.values) {
      expect(writingSystemPrompt(t), contains('only the new message text'));
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
}
