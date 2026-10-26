import 'dart:async';
import 'dart:convert';

import 'package:llamadart/llamadart.dart';

import '../../../core/models/bundled_models.dart';
import '../domain/action_guardrails.dart';
import '../domain/assistant_action.dart';
import '../domain/writing_tool.dart';
import 'assistant_prompt.dart';

/// Where a suggestion is, for the sheet's status line.
enum ExtractStage { preparing, loading, reading }

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
  ActionExtractor(
    this._models, {
    Future<LlamaEngine> Function(String path)? loadEngine,
    this.prepareTimeout = const Duration(minutes: 2),
    this.loadTimeout = const Duration(seconds: 45),
  }) : _loadEngine = loadEngine ?? _llama;

  final ModelInstaller _models;
  final Future<LlamaEngine> Function(String path) _loadEngine;

  /// First use copies the ~230 MB model out of the APK.
  final Duration prepareTimeout;
  final Duration loadTimeout;

  LlamaEngine? _engine;
  Future<LlamaEngine>? _loading;
  Timer? _idle;
  var _running = 0;

  static Future<LlamaEngine> _llama(String path) async {
    final engine = LlamaEngine(LlamaBackend());
    await engine.setModel(
      LlamaModel(ModelSource.path(path)),
      params: const ModelParams(contextSize: 2048, device: ComputeDevice.cpu),
    );
    return engine;
  }

  Future<LlamaEngine> _ready(void Function(ExtractStage)? onStage) {
    if (_engine case final engine?) return Future.value(engine);
    // A load that failed or timed out must not stay cached, or every later
    // attempt would wait on it forever.
    return _loading ??= () async {
      onStage?.call(ExtractStage.preparing);
      final path = await _models.ensure(BundledModel.actionModel).timeout(prepareTimeout);
      onStage?.call(ExtractStage.loading);
      return _engine = await _loadEngine(path).timeout(loadTimeout);
    }().whenComplete(() => _loading = null);
  }

  Future<ActionDraft> extract(
    String messageText,
    AssistantContext ctx, {
    void Function(ExtractStage stage)? onStage,
  }) async {
    _idle?.cancel();
    _running++;
    try {
      final engine = await _ready(onStage);
      onStage?.call(ExtractStage.reading);
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

  /// Writing help on [text] with [tool] (rewrite, grammar, summary, tone),
  /// on the same model.
  Future<String> write(String text, WritingTool tool, {void Function(ExtractStage stage)? onStage}) async {
    _idle?.cancel();
    _running++;
    try {
      final engine = await _ready(onStage);
      onStage?.call(ExtractStage.reading);
      final raw = await engine
          .create(
            [
              for (final (role, content) in writingTurns(tool, text))
                LlamaChatMessage.fromText(
                  role: switch (role) {
                    'system' => LlamaChatRole.system,
                    'assistant' => LlamaChatRole.assistant,
                    _ => LlamaChatRole.user,
                  },
                  text: content,
                ),
            ],
            params: GenerationParams(
              maxTokens: (text.length ~/ 2 + 64).clamp(64, 512),
              temp: tool == WritingTool.grammar ? 0 : 0.4,
            ),
            enableThinking: false,
          )
          .text()
          .timeout(const Duration(seconds: 45));
      return cleanWritingOutput(raw);
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
