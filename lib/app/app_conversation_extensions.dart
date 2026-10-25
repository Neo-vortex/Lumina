import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../core/media/ffmpeg_service.dart';
import '../core/media/waveform.dart';
import '../core/storage/app_preferences.dart';
import '../core/telegram/display.dart';
import '../core/telegram/telegram_cache.dart';
import '../core/theme/glow_colors.dart';
import '../features/assistant/data/action_extractor.dart';
import '../features/assistant/presentation/action_sheet.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/chat_info/presentation/compose_flows.dart';
import '../features/chat_info/presentation/screens/chat_info_screen.dart';
import '../features/auth/domain/auth_step.dart';
import '../features/conversation/bloc/conversation_cubit.dart';
import '../features/conversation/data/messages_repository.dart';
import '../features/conversation/presentation/widgets/conversation_extensions.dart';
import '../features/conversation/presentation/widgets/message_menu.dart';
import '../features/media/presentation/screens/send_media_screen.dart';
import '../features/conversation/presentation/widgets/send_orb.dart';
import '../features/media/presentation/widgets/attach_sheet.dart';
import '../features/transcription/data/transcription_center.dart';
import '../features/transcription/data/whisper_service.dart';
import '../features/transcription/presentation/widgets/dictation_bar.dart';
import '../features/transcription/presentation/widgets/transcript_view.dart';
import '../features/voice/data/voice_recorder.dart';
import '../features/voice/presentation/screens/video_note_recorder_screen.dart';
import '../features/voice/presentation/widgets/recording_bar.dart';

/// The app's implementation of the conversation hooks: wires media,
/// voice, dictation, AI actions and chat info into the conversation screen.
class AppConversationExtensions extends ConversationExtensions {
  AppConversationExtensions({
    required this.recorder,
    required this.transcripts,
    required this.prefs,
    required this.flows,
  });

  final VoiceRecorder recorder;
  final TranscriptionCenter transcripts;
  final AppPreferences prefs;
  final ComposeFlows flows;

  @override
  void openChatInfo(BuildContext context, td.Chat chat) =>
      Navigator.of(context).push(ChatInfoScreen.route(chat.id, openChat: flows.openChat));

  /// Dictation progress (Whisper running on the recorded speech).
  final _dictation = ValueNotifier<double?>(null);

  @override
  Listenable get composerListenable => Listenable.merge([recorder, _dictation]);

  // ---- AI actions (tiny on-device LLM) ---------------------------------------

  @override
  List<ExtraMenuEntry> menuEntries(td.Message message) => [
    if (messageText(message) != null)
      const ExtraMenuEntry(MessageAction.aiAction, Icons.auto_awesome_rounded, 'AI action: event, alarm, note'),
  ];

  @override
  Future<void> onMenuAction(BuildContext context, MessageAction action, td.Message message) async {
    if (action != MessageAction.aiAction) return;
    final text = messageText(message)?.text;
    if (text == null) return;
    final cache = context.read<TelegramCache>();
    final me = switch (context.read<AuthBloc>().state.step) {
      AuthReady(:final me) => me,
      _ => null,
    };
    await showAssistantActionSheet(
      context,
      messageText: text,
      assistantContext: AssistantContext(
        userName: Display.userName(me),
        username: me?.usernames?.activeUsernames.firstOrNull ?? '',
        senderName: message.isOutgoing ? 'the user' : Display.senderName(cache, message.senderId),
        messageTime: Display.messageDate(message),
        now: DateTime.now(),
      ),
    );
  }

  // ---- Transcription & dictation (phase 6) ----------------------------------

  @override
  Widget? voiceAccessory(BuildContext context, td.Message message) {
    final outgoing = message.isOutgoing;
    return TranscriptView(
      center: transcripts,
      message: message,
      color: outgoing ? GlowColors.onAccent : GlowColors.cyan,
    );
  }

  @override
  void onDictate(BuildContext context, td.Chat chat, TextEditingController text) => _dictate(context, chat, text);

  Future<void> _dictate(BuildContext context, td.Chat chat, TextEditingController text) async {
    final messenger = ScaffoldMessenger.of(context);
    if (recorder.phase != RecorderPhase.idle) return;
    final ok = await recorder.start(chat.id, forDictation: true);
    if (!ok && recorder.error != null) messenger.showSnackBar(SnackBar(content: Text(recorder.error!)));
  }

  /// Stops dictation, transcribes and inserts the text (auto-sends if the
  /// user opted in, spec §8.2).
  Future<void> _finishDictation(BuildContext context, td.Chat chat, TextEditingController text) async {
    final cubit = context.read<ConversationCubit>();
    final messenger = ScaffoldMessenger.of(context);
    await recorder.stop();
    final recording = recorder.take();
    if (recording == null) return;
    _dictation.value = 0;
    try {
      final t = await transcripts.whisper.transcribe(
        recording.wavPath,
        language: prefs.whisperLanguage,
        onProgress: (p) => _dictation.value = p,
      );
      if (t.text.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('No speech detected')));
        return;
      }
      final sel = text.selection;
      final at = sel.isValid ? sel.start : text.text.length;
      final before = text.text.substring(0, at);
      final insert = (before.isEmpty || before.endsWith(' ') ? '' : ' ') + t.text;
      text.value = TextEditingValue(
        text: before + insert + text.text.substring(sel.isValid ? sel.end : at),
        selection: TextSelection.collapsed(offset: at + insert.length),
      );
      if (prefs.dictationAutoSend) {
        final error = await cubit.send(text.text);
        if (error == null) {
          text.clear();
        } else {
          messenger.showSnackBar(SnackBar(content: Text(error)));
        }
      }
    } on TranscriptionFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      _dictation.value = null;
      File(recording.wavPath).delete().ignore();
    }
  }

  // ---- Voice messages (phase 5) ---------------------------------------------

  @override
  OrbMode? orbMode(BuildContext context, td.Chat chat) {
    if (_dictation.value != null) return OrbMode.busy;
    if (recorder.isActiveFor(chat.id) && recorder.dictation) return OrbMode.stop;
    if (!recorder.isActiveFor(chat.id) || recorder.dictation) return null;
    return switch (recorder.phase) {
      RecorderPhase.recording => OrbMode.stop,
      RecorderPhase.review => OrbMode.send,
      RecorderPhase.idle => null,
    };
  }

  @override
  Widget? recordingOverlay(BuildContext context, td.Chat chat) {
    final dictating = _dictation.value;
    if (dictating != null || (recorder.isActiveFor(chat.id) && recorder.dictation)) {
      return DictationBar(recorder: recorder, transcribing: dictating != null, progress: dictating ?? 0);
    }
    if (!recorder.isActiveFor(chat.id) || recorder.dictation) return null;
    return RecordingBar(recorder: recorder);
  }

  @override
  void onVoice(BuildContext context, td.Chat chat, TextEditingController text) {
    if (recorder.isActiveFor(chat.id) && recorder.dictation) {
      _finishDictation(context, chat, text);
    } else {
      _voice(context, chat);
    }
  }

  Future<void> _voice(BuildContext context, td.Chat chat) async {
    final cubit = context.read<ConversationCubit>();
    final messenger = ScaffoldMessenger.of(context);
    switch (recorder.phase) {
      case RecorderPhase.idle:
        final ok = await recorder.start(chat.id);
        if (ok) {
          cubit.chatAction(const td.ChatActionRecordingVoiceNote());
        } else if (recorder.error != null) {
          messenger.showSnackBar(SnackBar(content: Text(recorder.error!)));
        }
      case RecorderPhase.recording:
        await recorder.stop();
        cubit.chatAction(const td.ChatActionCancel());
        if (recorder.error != null && recorder.phase == RecorderPhase.idle) {
          messenger.showSnackBar(SnackBar(content: Text(recorder.error!)));
        }
      case RecorderPhase.review:
        final recording = recorder.take();
        if (recording == null || !context.mounted) return;
        final ffmpeg = context.read<FfmpegService>();
        final ogg = await ffmpeg.toVoiceNote(recording.wavPath);
        if (ogg == null) {
          messenger.showSnackBar(const SnackBar(content: Text('Could not encode the voice message')));
          return;
        }
        final error = await cubit.sendContent(
          td.InputMessageVoiceNote(
            voiceNote: td.InputFileLocal(path: ogg),
            duration: recording.duration.inSeconds,
            waveform: Waveform.encode(recording.waveform),
          ),
        );
        if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  // ---- Attachments (phase 4) -------------------------------------------------

  @override
  void onAttach(BuildContext context, td.Chat chat) => _attach(context, chat);

  Future<void> _attach(BuildContext context, td.Chat chat) async {
    final cubit = context.read<ConversationCubit>();
    final messages = context.read<MessagesRepository>();
    final paths = await pickAttachments(context, context.read<FfmpegService>());
    if (paths.isEmpty || !context.mounted) return;
    if (paths.length == 1 && paths.first == videoNoteChoice) {
      final note = await VideoNoteRecorderScreen.open(context);
      if (note != null) {
        final error = await cubit.sendContent(note);
        if (error != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
        }
      }
      return;
    }
    final isBot = switch (context.read<AuthBloc>().state.step) {
      AuthReady(:final capabilities) => capabilities.isBot,
      _ => false,
    };
    final request = await SendMediaScreen.open(
      context,
      paths: paths,
      allowViewOnce: !isBot && chat.type is td.ChatTypePrivate,
      parseCaption: messages.parseMarkdown,
    );
    if (request == null) return;
    final error = request.asAlbum ? await cubit.sendAlbum(request.contents) : await _sendEach(cubit, request.contents);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  static Future<String?> _sendEach(ConversationCubit cubit, List<td.InputMessageContent> contents) async {
    for (final c in contents) {
      final error = await cubit.sendContent(c);
      if (error != null) return error;
    }
    return null;
  }
}
