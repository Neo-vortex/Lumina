import 'dart:async';

import 'package:flutter/services.dart';

import '../bloc/downloads_cubit.dart';

/// The download notifications, implemented natively.
abstract interface class DownloadsChannel {
  Future<void> progress(int count, int percent);
  Future<void> clearProgress();
  Future<void> completed(int id, String name, String path);

  /// `pauseAll` (notification action) or `open:<path>` (a tapped
  /// "Downloaded" notification).
  Stream<String> get events;
}

/// [DownloadsChannel] over `dev.lumina/downloads`.
class MethodDownloadsChannel implements DownloadsChannel {
  static const _methods = MethodChannel('dev.lumina/downloads');
  static const _events = EventChannel('dev.lumina/downloads/events');

  Future<void> _call(String method, [Object? args]) async {
    try {
      await _methods.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // Tests and previews: no native side.
    } on PlatformException {
      // Notifications are a nicety; the list still works.
    }
  }

  @override
  Future<void> progress(int count, int percent) => _call('progress', {'count': count, 'percent': percent});

  @override
  Future<void> clearProgress() => _call('clearProgress');

  @override
  Future<void> completed(int id, String name, String path) =>
      _call('completed', {'id': id, 'name': name, 'path': path});

  @override
  Stream<String> get events => _events.receiveBroadcastStream().map((e) => '$e');
}

/// One quiet "Downloading N files · X%" notification while downloads run
/// and a "Downloaded" one per finished file (not while the screen shows).
class DownloadNotifier {
  DownloadNotifier({
    required DownloadsCubit cubit,
    required DownloadsChannel channel,
    bool Function()? screenVisible,
    void Function(String path)? openFile,
  }) : _cubit = cubit,
       _channel = channel,
       _screenVisible = screenVisible ?? (() => false),
       _openFile = openFile {
    _state = _cubit.stream.listen(_onState);
    _events = _channel.events.listen(_onEvent, onError: (Object _) {});
    _onState(_cubit.state);
  }

  final DownloadsCubit _cubit;
  final DownloadsChannel _channel;
  final bool Function() _screenVisible;
  final void Function(String path)? _openFile;
  late final StreamSubscription<DownloadsState> _state;
  late final StreamSubscription<String> _events;
  (int, int)? _shown;
  Set<int> _active = const {};

  void _onState(DownloadsState s) {
    final active = {for (final i in s.active) i.fileId};
    for (final i in s.completed) {
      if (_active.contains(i.fileId) && !_screenVisible()) {
        _channel.completed(i.fileId, i.name, i.file?.local.path ?? '').ignore();
      }
    }
    _active = active;
    if (s.active.isEmpty) {
      if (_shown != null) _channel.clearProgress().ignore();
      _shown = null;
      return;
    }
    final percent = s.totalSize > 0 ? (s.downloadedSize * 100 ~/ s.totalSize).clamp(0, 100) : 0;
    final next = (s.active.length, percent);
    if (next == _shown) return;
    _shown = next;
    _channel.progress(next.$1, next.$2).ignore();
  }

  void _onEvent(String e) {
    if (e == 'pauseAll') {
      _pauseAll();
    } else if (e.startsWith('open:')) {
      _openFile?.call(e.substring(5));
    }
  }

  Future<void> _pauseAll() async {
    try {
      await _cubit.setAllPaused(true);
    } on Exception {
      // The list re-syncs; the notification stays as it was.
    }
  }

  void dispose() {
    _state.cancel();
    _events.cancel();
  }
}
