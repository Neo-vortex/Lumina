// Opt-in model comparison for AI actions (JSON mode, few-shot prompt).
//   LUMINA_LLM_MODELS=a.gguf,b.gguf flutter test test/integration/llm_eval_test.dart
@Tags(['llm'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:lumina/features/assistant/data/assistant_prompt.dart';
import 'package:lumina/features/assistant/domain/action_guardrails.dart';
import 'package:lumina/features/assistant/domain/assistant_action.dart';

const cases = <String, ActionKind>{
  'Dentist appointment on Tuesday at 3pm, clinic on Main St': ActionKind.calendar,
  'Can you wake me up at 6:30 tomorrow? big day': ActionKind.alarm,
  "Don't forget to call mom in 20 minutes": ActionKind.reminder,
  'The wifi password is Sunflower-42 and the door code is 1984': ActionKind.note,
  'haha that was so funny 😂': ActionKind.none,
  "Team lunch next Friday 12:30 at Luigi's": ActionKind.calendar,
  'remind me to send the invoice tomorrow morning': ActionKind.reminder,
  'Our new address: 221B Baker Street, London NW1 6XE': ActionKind.note,
  'ok see you': ActionKind.none,
  'Flight LH 404 departs Nov 3 at 07:10 from gate B12': ActionKind.calendar,
  'set an alarm for 5:45 please, early train': ActionKind.alarm,
  'Shopping list: eggs, milk, rice, 2 avocados': ActionKind.note,
  'what do you think about the new phone?': ActionKind.none,
  'Pick up the kids at 4 today, dont forget!': ActionKind.reminder,
};

/// Held out: written after the prompt and guardrails were final; never used
/// for tuning. Report both, decide on this one.
const heldOut = <String, ActionKind>{
  'Parents evening at school, Thursday 18:30': ActionKind.calendar,
  'yoga with Mia sunday 9 am at the park': ActionKind.calendar,
  'Please ring me at 7 so I make the bus': ActionKind.alarm,
  'need to be up at 5:15 tomorrow, airport run': ActionKind.alarm,
  'ping me in 10 min to check the oven': ActionKind.reminder,
  'remember to renew your passport next week': ActionKind.reminder,
  'Guest wifi: LuminaGuest / pw: glow2026': ActionKind.note,
  'Recipe: 2 cups flour, 1 egg, pinch of salt, bake 20 min': ActionKind.note,
  'My new number is +44 7700 900123': ActionKind.note,
  'that movie was amazing': ActionKind.none,
  'thanks!!': ActionKind.none,
  'are you coming or not?': ActionKind.none,
  'Interview with Acme on 12 November at 11:00 (video call)': ActionKind.calendar,
  'Payday is the 28th, pay the rent then': ActionKind.reminder,
  'ok I will call you later': ActionKind.none,
  'Train tickets: coach 9, seats 41 and 42, ref QX7P2': ActionKind.note,
};

void main() {
  final models = (Platform.environment['LUMINA_LLM_MODELS'] ?? '')
      .split(',')
      .where((p) => p.isNotEmpty)
      .toList();
  final labelMode = Platform.environment['LUMINA_LLM_MODE'] == 'label';
  final now = DateTime(2026, 10, 25, 14);

  for (final path in models) {
    test('eval ${path.split('/').last}', () async {
      final engine = LlamaEngine(LlamaBackend());
      await engine.setModel(
        LlamaModel(ModelSource.path(path)),
        params: const ModelParams(contextSize: 2048, device: ComputeDevice.cpu),
      );
      final useHeldOut = Platform.environment['LUMINA_LLM_SET'] == 'heldout';
      final set = useHeldOut ? heldOut : cases;
      var correct = 0;
      var guarded = 0;
      var totalMs = 0;
      for (final e in set.entries) {
        final sw = Stopwatch()..start();
        final raw = await engine
            .create(
              labelMode
                  ? labelPrompt(e.key, userName: 'Ada', senderName: 'Bob')
                  : classificationPrompt(
                      e.key,
                      userName: 'Ada',
                      username: 'ada',
                      senderName: 'Bob',
                      now: now,
                    ),
              params: const GenerationParams(maxTokens: 120, temp: 0, topK: 1),
              responseFormat: {
                'type': 'json_schema',
                'json_schema': {'name': 'action', 'schema': labelMode ? labelSchema : actionSchema},
              },
              enableThinking: false,
            )
            .text();
        totalMs += sw.elapsedMilliseconds;
        ActionKind kind;
        try {
          final json =
              jsonDecode(raw.substring(raw.indexOf('{'), raw.lastIndexOf('}') + 1)) as Map<String, dynamic>;
          kind = ActionDraft.fromModel(json, messageText: e.key, now: now).kind;
        } catch (_) {
          kind = ActionKind.none;
        }
        final ok = kind == e.value;
        if (ok) correct++;
        final finalKind = ActionGuardrails.decide(kind, e.key, now);
        if (finalKind == e.value) {
          guarded++;
        } else {
          // ignore: avoid_print
          print('  ✗✗ final ${finalKind.name} (want ${e.value.name}) ${e.key}');
        }
        // ignore: avoid_print
        print(
          '  ${ok ? '✓' : '✗'} ${kind.name.padRight(8)} (want ${e.value.name}) ${e.key}  ${raw.replaceAll('\n', ' ')}',
        );
      }
      // ignore: avoid_print
      print(
        'RESULT ${useHeldOut ? 'held-out' : 'dev'} ${path.split('/').last}: model $correct/${set.length}, '
        'with guardrails $guarded/${set.length}, avg ${totalMs ~/ set.length} ms',
      );
      await engine.dispose();
    }, timeout: const Timeout(Duration(minutes: 15)));
  }
}
