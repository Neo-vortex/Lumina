import 'package:flutter/foundation.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/storage/app_preferences.dart';
import '../../../core/telegram/file_store.dart';
import 'whisper_service.dart';

enum TranscriptStatus { working, done, failed }

class TranscriptEntry {
  const TranscriptEntry({
    required this.status,
    this.text,
    this.translatedText,
    this.language,
    this.error,
    this.progress = 0,
    this.showTranslation = false,
    this.collapsed = false,
  });

  final TranscriptStatus status;
  final String? text;
  final String? translatedText;
  final String? language;
  final String? error;
  final double progress;
  final bool showTranslation;
  final bool collapsed;

  TranscriptEntry copyWith({
    TranscriptStatus? status,
    String? text,
    String? translatedText,
    String? language,
    String? Function()? error,
    double? progress,
    bool? showTranslation,
    bool? collapsed,
  }) => TranscriptEntry(
    status: status ?? this.status,
    text: text ?? this.text,
    translatedText: translatedText ?? this.translatedText,
    language: language ?? this.language,
    error: error != null ? error() : this.error,
    progress: progress ?? this.progress,
    showTranslation: showTranslation ?? this.showTranslation,
    collapsed: collapsed ?? this.collapsed,
  );
}

/// Transcripts of voice messages, kept for the app session (spec §8.2:
/// "Transcribe" → collapsible transcript, "Translate to English" re-runs
/// Whisper with translate).
class TranscriptionCenter extends ChangeNotifier {
  TranscriptionCenter({required this._whisper, required this._files, required this._prefs});

  final WhisperService _whisper;
  final FileStore _files;
  final AppPreferences _prefs;
  final _entries = <String, TranscriptEntry>{};

  WhisperService get whisper => _whisper;

  static String keyOf(td.Message m) => '${m.chatId}:${m.id}';

  TranscriptEntry? entry(td.Message m) => _entries[keyOf(m)];

  td.File? _audioOf(td.Message m) => switch (m.content) {
    td.MessageVoiceNote(:final voiceNote) => voiceNote.voice,
    td.MessageVideoNote(:final videoNote) => videoNote.video,
    td.MessageAudio(:final audio) => audio.audio,
    _ => null,
  };

  bool canTranscribe(td.Message m) => _audioOf(m) != null;

  Future<void> transcribe(td.Message m, {bool translate = false}) async {
    final key = keyOf(m);
    final file = _audioOf(m);
    if (file == null) return;
    final existing = _entries[key];
    if (existing?.status == TranscriptStatus.working) return;
    if (translate && existing?.translatedText != null) {
      _set(key, existing!.copyWith(showTranslation: true, collapsed: false));
      return;
    }
    _set(
      key,
      (existing ?? const TranscriptEntry(status: TranscriptStatus.working)).copyWith(
        status: TranscriptStatus.working,
        progress: 0,
        error: () => null,
      ),
    );
    try {
      final path = await _files.downloadAndWait(file.id);
      final t = await _whisper.transcribe(
        path,
        translate: translate,
        language: translate ? 'auto' : _prefs.whisperLanguage,
        onProgress: (p) => _set(key, _entries[key]!.copyWith(progress: p)),
      );
      final text = t.text.isEmpty ? '(no speech detected)' : t.text;
      _set(
        key,
        _entries[key]!.copyWith(
          status: TranscriptStatus.done,
          text: translate ? null : text,
          translatedText: translate ? text : null,
          language: t.language,
          showTranslation: translate,
          collapsed: false,
        ),
      );
    } on TranscriptionFailure catch (e) {
      _set(key, _entries[key]!.copyWith(status: TranscriptStatus.failed, error: () => e.message));
    } catch (e) {
      _set(key, _entries[key]!.copyWith(status: TranscriptStatus.failed, error: () => '$e'));
    }
  }

  void toggleCollapsed(td.Message m) {
    final e = entry(m);
    if (e != null) _set(keyOf(m), e.copyWith(collapsed: !e.collapsed));
  }

  void showOriginal(td.Message m) {
    final e = entry(m);
    if (e == null) return;
    if (e.text == null) {
      transcribe(m);
    } else {
      _set(keyOf(m), e.copyWith(showTranslation: false));
    }
  }

  void _set(String key, TranscriptEntry e) {
    _entries[key] = e;
    notifyListeners();
  }
}
