import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../../../core/media/ffmpeg_service.dart';
import '../../../core/media/waveform.dart';

enum RecorderPhase { idle, recording, review }

/// A finished recording, ready to send or transcribe.
class Recording {
  const Recording({required this.wavPath, required this.duration, required this.waveform});

  /// 16 kHz mono 16-bit PCM WAV (spec §7.2), also usable by Whisper.
  final String wavPath;
  final Duration duration;

  /// 0..31 levels for display and for TDLib's voice-note waveform.
  final List<int> waveform;
}

/// One recording at a time, app-wide. Records 16 kHz mono WAV (spec §7.2)
/// with a live level meter for the waveform shown while recording.
class VoiceRecorder extends ChangeNotifier {
  VoiceRecorder(this._ffmpeg);

  final FfmpegService _ffmpeg;
  final _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amp;
  Timer? _ticker;
  DateTime? _startedAt;

  RecorderPhase phase = RecorderPhase.idle;

  /// Chat the recording belongs to.
  int? chatId;

  /// Purpose: a voice message, or dictation for the text field.
  bool dictation = false;

  Duration elapsed = Duration.zero;
  final List<double> levels = [];
  Recording? result;
  String? error;

  static const maxDuration = Duration(minutes: 30);

  bool isActiveFor(int chat) => phase != RecorderPhase.idle && chatId == chat;

  Future<bool> start(int chat, {bool forDictation = false}) async {
    if (phase != RecorderPhase.idle) return false;
    if (!await _recorder.hasPermission()) {
      error = 'Microphone permission is needed to record.';
      notifyListeners();
      return false;
    }
    final path = await _ffmpeg.tempPath('wav');
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        noiseSuppress: true,
        autoGain: true,
      ),
      path: path,
    );
    chatId = chat;
    dictation = forDictation;
    phase = RecorderPhase.recording;
    error = null;
    levels.clear();
    result = null;
    _startedAt = DateTime.now();
    elapsed = Duration.zero;
    _amp = _recorder.onAmplitudeChanged(const Duration(milliseconds: 80)).listen((a) {
      // dBFS (−160..0) → 0..1, with a floor so quiet speech still shows.
      final level = math.pow(10, (a.current.clamp(-60.0, 0.0)) / 30).toDouble();
      levels.add(level);
      notifyListeners();
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      elapsed = DateTime.now().difference(_startedAt!);
      if (elapsed >= maxDuration) stop();
      notifyListeners();
    });
    notifyListeners();
    return true;
  }

  /// Stops recording and moves to review. Returns the recording.
  Future<Recording?> stop() async {
    if (phase != RecorderPhase.recording) return result;
    await _amp?.cancel();
    _ticker?.cancel();
    final path = await _recorder.stop();
    elapsed = DateTime.now().difference(_startedAt!);
    if (path == null || elapsed < const Duration(milliseconds: 400)) {
      // Too short to be intentional (UX-30): discard quietly.
      await cancel();
      error = 'Hold on a little longer to record.';
      notifyListeners();
      return null;
    }
    List<int> wave;
    try {
      wave = Waveform.fromWav(await File(path).readAsBytes());
    } catch (_) {
      wave = Waveform.resample(Waveform.normalise(levels), Waveform.samples);
    }
    result = Recording(wavPath: path, duration: elapsed, waveform: wave);
    phase = RecorderPhase.review;
    notifyListeners();
    return result;
  }

  Future<void> cancel() async {
    await _amp?.cancel();
    _ticker?.cancel();
    if (phase == RecorderPhase.recording) await _recorder.cancel();
    final p = result?.wavPath;
    if (p != null) await File(p).delete().catchError((_) => File(p));
    _reset();
  }

  /// Hands the recording over (the caller owns its file now).
  Recording? take() {
    final r = result;
    _reset();
    return r;
  }

  void _reset() {
    phase = RecorderPhase.idle;
    chatId = null;
    result = null;
    levels.clear();
    elapsed = Duration.zero;
    notifyListeners();
  }

  @override
  void dispose() {
    _amp?.cancel();
    _ticker?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}
