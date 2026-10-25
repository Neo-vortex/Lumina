import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:whisper_edge/whisper_edge.dart';

import '../../../core/media/ffmpeg_service.dart';
import '../../../core/models/bundled_models.dart';

/// Result of a transcription.
class Transcript {
  const Transcript({required this.text, required this.language, required this.translated});

  final String text;
  final String? language;

  /// Text was translated to English (Whisper's translate task).
  final bool translated;
}

class TranscriptionFailure implements Exception {
  const TranscriptionFailure(this.message, {this.outOfMemory = false});
  final String message;
  final bool outOfMemory;

  @override
  String toString() => message;
}

/// Offline speech-to-text with the bundled Whisper base model (spec §8).
///
/// * Any audio is converted to 16 kHz mono WAV first (Telegram voice notes
///   are OGG/Opus, which whisper_edge cannot decode on Android).
/// * Audio longer than 5 minutes is transcribed in 30 s chunks (§10.4).
/// * One run at a time; the model is unloaded after a short idle period to
///   give its memory back.
class WhisperService {
  WhisperService({required this._ffmpeg, required this._models});

  final FfmpegService _ffmpeg;
  final ModelInstaller _models;
  WhisperTranscriber? _transcriber;
  Timer? _idle;
  Future<void> _queue = Future.value();

  static const longAudio = Duration(minutes: 5);
  static const chunk = Duration(seconds: 30);
  static const sampleRate = 16000;

  /// Transcribes [audioPath] (any format). [translate] = Whisper's
  /// translate-to-English task. [language] "auto" or an ISO code.
  Future<Transcript> transcribe(
    String audioPath, {
    bool translate = false,
    String language = 'auto',
    void Function(double progress)? onProgress,
  }) {
    final run = _queue.then((_) => _run(audioPath, translate, language, onProgress));
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<Transcript> _run(
    String audioPath,
    bool translate,
    String language,
    void Function(double)? onProgress,
  ) async {
    _idle?.cancel();
    final wav = audioPath.toLowerCase().endsWith('.wav') ? audioPath : await _ffmpeg.toWhisperWav(audioPath);
    if (wav == null) {
      throw const TranscriptionFailure('This audio format could not be converted for transcription.');
    }
    try {
      final transcriber = _transcriber ??= await WhisperTranscriber.load(
        await _models.ensure(BundledModel.whisperBase),
      );
      final pcm = await _readPcm(wav);
      final duration = Duration(milliseconds: pcm.length * 1000 ~/ sampleRate);
      final parts = <String>[];
      String? detected;
      if (duration <= longAudio) {
        final r = await transcriber.transcribe(
          pcm,
          language: language,
          translate: translate,
          onProgress: (p) => onProgress?.call(p / 100),
        );
        parts.add(r.segments.map((s) => s.text.trim()).join(' '));
        detected = r.language;
      } else {
        final ranges = chunkRanges(pcm.length, sampleRate: sampleRate, chunk: chunk);
        for (var i = 0; i < ranges.length; i++) {
          final (start, end) = ranges[i];
          final r = await transcriber.transcribe(
            Float32List.sublistView(pcm, start, end),
            language: detected ?? language,
            translate: translate,
            onProgress: (p) => onProgress?.call((i + p / 100) / ranges.length),
          );
          detected ??= r.language;
          parts.add(r.segments.map((s) => s.text.trim()).join(' '));
        }
      }
      return Transcript(
        text: parts.where((p) => p.isNotEmpty).join(' ').trim(),
        language: detected,
        translated: translate,
      );
    } on OutOfMemoryError {
      _unload();
      throw const TranscriptionFailure('Not enough memory. Try a shorter recording.', outOfMemory: true);
    } on WhisperException catch (e) {
      throw TranscriptionFailure('Transcription failed: ${e.message}');
    } finally {
      if (wav != audioPath) File(wav).delete().ignore();
      _idle = Timer(const Duration(minutes: 2), _unload);
    }
  }

  void cancel() => _transcriber?.cancel();

  /// Frees the model once the current run (if any) finishes; used when
  /// Android reports memory pressure.
  void releaseMemory() {
    _queue = _queue.then((_) {
      _idle?.cancel();
      _unload();
    });
  }

  void _unload() {
    _transcriber?.dispose();
    _transcriber = null;
  }

  /// 16-bit PCM WAV → float32 samples in −1..1.
  static Future<Float32List> _readPcm(String wav) async {
    final bytes = await File(wav).readAsBytes();
    var offset = 44;
    final view = ByteData.sublistView(bytes);
    // Find the "data" chunk (ffmpeg may add LIST chunks).
    for (var p = 12; p + 8 <= bytes.length;) {
      final id = String.fromCharCodes(bytes.sublist(p, p + 4));
      final size = view.getUint32(p + 4, Endian.little);
      if (id == 'data') {
        offset = p + 8;
        break;
      }
      p += 8 + size + (size & 1);
    }
    final count = (bytes.length - offset) ~/ 2;
    final out = Float32List(count);
    for (var i = 0; i < count; i++) {
      out[i] = view.getInt16(offset + i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  void dispose() {
    _idle?.cancel();
    _unload();
  }
}

/// [start, end) sample ranges of at most [chunk] each.
List<(int, int)> chunkRanges(int samples, {required int sampleRate, required Duration chunk}) {
  final size = sampleRate * chunk.inMilliseconds ~/ 1000;
  return [for (var s = 0; s < samples; s += size) (s, (s + size).clamp(0, samples))];
}
