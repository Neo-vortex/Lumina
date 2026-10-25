import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:just_audio/just_audio.dart';

import '../storage/app_preferences.dart';
import '../telegram/file_store.dart';
import 'tdlib_stream_server.dart';

/// What the shared audio player is doing.
@immutable
class PlaybackState {
  const PlaybackState({
    this.key,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1,
  });

  /// Identifies the playing item ("chatId:messageId"), null when idle.
  final String? key;
  final bool playing;
  final Duration position;
  final Duration duration;
  final double speed;

  bool isFor(String k) => key == k;

  PlaybackState copyWith({
    String? Function()? key,
    bool? playing,
    Duration? position,
    Duration? duration,
    double? speed,
  }) => PlaybackState(
    key: key != null ? key() : this.key,
    playing: playing ?? this.playing,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    speed: speed ?? this.speed,
  );
}

/// One player for voice notes and music: starting another item stops the
/// current one. Plays the local file when TDLib has it, otherwise streams
/// through the loopback server. Speed follows [AppPreferences.playbackSpeed]
/// (0.5–4×, user request).
class AudioPlayback {
  AudioPlayback({required this._files, required this._stream, required this._prefs}) {
    _subs.addAll([
      _player.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) {
          _player.pause();
          _player.seek(Duration.zero);
          _onCompleted?.call();
          _set(state.value.copyWith(playing: false, position: Duration.zero));
        } else {
          _set(state.value.copyWith(playing: s.playing));
        }
      }),
      _player.positionStream.listen((p) => _set(state.value.copyWith(position: p))),
      _player.durationStream.listen((d) => _set(state.value.copyWith(duration: d ?? Duration.zero))),
    ]);
  }

  final FileStore _files;
  final TdStreamServer _stream;
  final AppPreferences _prefs;
  final _player = AudioPlayer();
  final _subs = <StreamSubscription<Object?>>[];
  VoidCallback? _onCompleted;

  final state = ValueNotifier(const PlaybackState());

  void _set(PlaybackState s) => state.value = s;

  /// Plays [file] for [key], or toggles pause if it is already current.
  Future<void> toggle(
    String key,
    td.File file, {
    String mime = 'audio/ogg',
    VoidCallback? onCompleted,
  }) async {
    if (state.value.isFor(key)) {
      _player.playing ? await _player.pause() : await _player.play();
      return;
    }
    await _player.stop();
    _onCompleted = onCompleted;
    final f = _files[file.id] ?? file;
    final speed = _prefs.playbackSpeed;
    _set(PlaybackState(key: key, speed: speed));
    if (f.local.isDownloadingCompleted && f.local.path.isNotEmpty) {
      await _player.setFilePath(f.local.path);
    } else {
      final url = await _stream.urlFor(f, mimeType: mime);
      await _player.setUrl(url.toString());
    }
    await _player.setSpeed(speed);
    unawaited(_player.play());
  }

  Future<void> seek(String key, Duration to) async {
    if (state.value.isFor(key)) await _player.seek(to);
  }

  /// Cycles 1 → 1.5 → 2 → 3 → 4 → 0.75 → 1 and remembers the choice.
  Future<void> cycleSpeed() async {
    const steps = [1.0, 1.5, 2.0, 3.0, 4.0, 0.75];
    final i = steps.indexWhere((s) => (s - state.value.speed).abs() < 0.01);
    final next = steps[(i + 1) % steps.length];
    _prefs.playbackSpeed = next;
    await _player.setSpeed(next);
    _set(state.value.copyWith(speed: next));
  }

  Future<void> stop() async {
    await _player.stop();
    _set(const PlaybackState());
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
  }
}
