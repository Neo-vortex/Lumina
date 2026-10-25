// Opt-in: runs the real bundled FunctionGemma GGUF on the host CPU.
//   LUMINA_LLM=1 flutter test test/integration/llm_smoke_test.dart
@Tags(['llm'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:lumina/features/assistant/data/assistant_prompt.dart';
import 'package:lumina/features/assistant/domain/assistant_action.dart';

void main() {
  final enabled = Platform.environment['LUMINA_LLM'] == '1';
  final now = DateTime(2026, 10, 25, 14);

  test(
    'FunctionGemma picks sensible actions (function calling)',
    () async {
      final engine = LlamaEngine(LlamaBackend());
      await engine.setModel(
        LlamaModel(ModelSource.path('assets/models/SmolLM2-360M-Instruct-Q4_0.gguf')),
        params: const ModelParams(contextSize: 2048, device: ComputeDevice.cpu),
      );
      final tools = assistantTools();
      final cases = {
        'Dentist appointment on Tuesday at 3pm, clinic on Main St': ActionKind.calendar,
        'Can you wake me up at 6:30 tomorrow? big day': ActionKind.alarm,
        "Don't forget to call mom in 20 minutes": ActionKind.reminder,
        'The wifi password is Sunflower-42 and the door code is 1984': ActionKind.note,
        'haha that was so funny 😂': ActionKind.none,
        'Team lunch next Friday 12:30 at Luigi\'s': ActionKind.calendar,
        'remind me to send the invoice tomorrow morning': ActionKind.reminder,
      };
      var correct = 0;
      for (final e in cases.entries) {
        final sw = Stopwatch()..start();
        final completion = await engine
            .create(
              assistantPrompt(e.key, userName: 'Ada', username: 'ada', senderName: 'Bob', now: now),
              tools: tools,
              toolChoice: ToolChoice.required,
              params: const GenerationParams(maxTokens: 160, temp: 0, topK: 1),
              enableThinking: false,
            )
            .collect();
        final draft = draftFromToolCalls(
          [for (final c in completion.toolCalls) (name: c.name, arguments: c.arguments)],
          messageText: e.key,
          now: now,
        );
        final ok = draft.kind == e.value;
        if (ok) correct++;
        // ignore: avoid_print
        print(
          '${ok ? '✓' : '✗'} ${sw.elapsedMilliseconds} ms  ${e.key}\n    → ${completion.toolCalls.map((c) => '${c.name}${c.arguments}').join(', ')} ${completion.text}\n    → ${draft.kind} "${draft.title}" ${draft.when}',
        );
      }
      // ignore: avoid_print
      print('accuracy: $correct/${cases.length}');
      await engine.dispose();
      expect(correct, greaterThanOrEqualTo(cases.length - 2));
    },
    skip: enabled ? false : 'set LUMINA_LLM=1',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
