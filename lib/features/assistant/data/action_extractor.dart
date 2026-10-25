import 'dart:async';
import 'dart:convert';

import 'package:llamadart/llamadart.dart';

import '../../../core/models/bundled_models.dart';
import '../domain/action_guardrails.dart';
import '../domain/assistant_action.dart';
import 'assistant_prompt.dart';

/// Who is asking, so the model can tell "me" from the sender.
class AssistantContext {
  const AssistantContext({
    required this.userName,
    required this.username,
    required this.senderName,
    required this.messageTime,
    required this.now,
  });

  final String userName;
  final String username;
  final String senderName;
  final DateTime messageTime;
  final DateTime now;
}

/// Runs SmolLM2-360M-Instruct (bundled, Q4_0 GGUF) through llama.cpp on
/// the CPU to label a message as a calendar event, alarm, reminder, note or
/// nothing. Output is constrained to a JSON schema so it always parses;
/// [ActionGuardrails] settle unambiguous phrasing and [DateResolver] works
/// out dates and times.
class ActionExtractor {
  ActionExtractor(this._models);

  final ModelInstaller _models;
  LlamaEngine? _engine;
  Future<LlamaEngine>? _loading;
  Timer? _idle;
  var _running = 0;

  Future<LlamaEngine> _ready() => _loading ??= () async {
    final path = await _models.ensure(BundledModel.actionModel);
    final engine = LlamaEngine(LlamaBackend());
    await engine.setModel(
      LlamaModel(ModelSource.path(path)),
      params: const ModelParams(contextSize: 2048, device: ComputeDevice.cpu),
    );
    return _engine = engine;
  }();

  Future<ActionDraft> extract(String messageText, AssistantContext ctx) async {
    _idle?.cancel();
    _running++;
    try {
      final engine = await _ready();
      final raw = await engine
          .create(
            labelPrompt(messageText, userName: ctx.userName, senderName: ctx.senderName),
            params: const GenerationParams(maxTokens: 60, temp: 0, topK: 1),
            responseFormat: const {
              'type': 'json_schema',
              'json_schema': {'name': 'action', 'schema': labelSchema},
            },
            enableThinking: false,
          )
          .text()
          .timeout(const Duration(seconds: 20));
      Map<String, dynamic> json;
      try {
        json = jsonDecode(raw.substring(raw.indexOf('{'), raw.lastIndexOf('}') + 1)) as Map<String, dynamic>;
      } on FormatException {
        json = const {'action': 'none'};
      }
      final draft = ActionDraft.fromModel(json, messageText: messageText, now: ctx.now);
      draft.kind = ActionGuardrails.decide(draft.kind, messageText, ctx.now);
      if (draft.kind == ActionKind.note && draft.notes.isEmpty) draft.notes = messageText;
      return draft;
    } finally {
      _running--;
      _idle = Timer(const Duration(minutes: 2), unload);
    }
  }

  /// Frees the model unless a suggestion is being worked out right now.
  Future<void> releaseMemory() async {
    if (_running > 0) return;
    _idle?.cancel();
    await unload();
  }

  Future<void> unload() async {
    final e = _engine;
    _engine = null;
    _loading = null;
    await e?.dispose();
  }
}
