import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/engine_params.dart';

/// What the engine reports (from tgcalls via NativeCall).
sealed class EngineEvent {
  const EngineEvent();
}

/// tgcalls connection state: see [EngineConnection].
final class EngineStateChanged extends EngineEvent {
  const EngineStateChanged(this.state);
  final EngineConnection state;
}

final class EngineSignalBars extends EngineEvent {
  const EngineSignalBars(this.bars);
  final int bars;
}

final class EngineAudioLevels extends EngineEvent {
  const EngineAudioLevels(this.mine, this.theirs);
  final double mine;
  final double theirs;
}

/// The other side muted / turned video on or off.
final class EngineRemoteMedia extends EngineEvent {
  const EngineRemoteMedia({required this.muted, required this.videoOn});
  final bool muted;
  final bool videoOn;
}

/// Data for the other side, to send through TDLib.
final class EngineSignaling extends EngineEvent {
  const EngineSignaling(this.data);
  final Uint8List data;
}

final class EngineStopped extends EngineEvent {
  const EngineStopped({required this.debugLog, required this.ratingSuggested});
  final String debugLog;
  final bool ratingSuggested;
}

enum EngineConnection { waitInit, waitInitAck, established, failed, reconnecting }

typedef EngineCapabilities = ({List<String> versions, int maxLayer, bool deviceAec, bool deviceNs});

/// The native call engine (one call at a time).
abstract interface class CallEngine {
  /// False when this build has no engine (calls are then unavailable).
  Future<bool> get available;

  /// tgcalls protocol versions and maximum layer (for CallProtocol), and
  /// whether the device has its own echo canceller / noise suppressor.
  Future<EngineCapabilities> capabilities();

  Future<void> start(EngineParams params);
  Future<void> receiveSignaling(Uint8List data);
  Future<void> setMuted(bool muted);

  /// Ends the call; [EngineStopped] follows.
  Future<void> stop();

  Stream<EngineEvent> get events;
}

/// [CallEngine] over the "dev.lumina/calls" channels (CallChannel.kt).
class ChannelCallEngine implements CallEngine {
  ChannelCallEngine();

  static const _methods = MethodChannel('dev.lumina/calls');
  static const _events = EventChannel('dev.lumina/calls/events');

  late final Stream<EngineEvent> _stream = _events
      .receiveBroadcastStream()
      .map((e) => parseEngineEvent(e as Map<Object?, Object?>))
      .where((e) => e != null)
      .cast<EngineEvent>();

  @override
  Future<bool> get available async {
    try {
      return await _methods.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      return false; // Tests, or a platform without the channel.
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<EngineCapabilities> capabilities() async {
    final r = await _methods.invokeMapMethod<String, Object?>('capabilities') ?? const {};
    return (
      versions: [for (final v in (r['versions'] as List? ?? const [])) v as String],
      maxLayer: r['maxLayer'] as int? ?? 92,
      deviceAec: r['deviceAec'] == true,
      deviceNs: r['deviceNs'] == true,
    );
  }

  @override
  Future<void> start(EngineParams params) => _methods.invokeMethod('start', params.toMap());

  @override
  Future<void> receiveSignaling(Uint8List data) => _methods.invokeMethod('receiveSignaling', data);

  @override
  Future<void> setMuted(bool muted) => _methods.invokeMethod('setMuted', muted);

  @override
  Future<void> stop() => _methods.invokeMethod('stop');

  @override
  Stream<EngineEvent> get events => _stream;
}

/// Decodes one event map sent by CallChannel.kt; null for unknown types.
EngineEvent? parseEngineEvent(Map<Object?, Object?> e) => switch (e['type']) {
  'state' => EngineStateChanged(switch (e['value']) {
    1 => EngineConnection.waitInit,
    2 => EngineConnection.waitInitAck,
    3 => EngineConnection.established,
    5 => EngineConnection.reconnecting,
    _ => EngineConnection.failed,
  }),
  'signalBars' => EngineSignalBars(e['value'] as int),
  'audioLevels' => EngineAudioLevels((e['mine'] as num).toDouble(), (e['theirs'] as num).toDouble()),
  // tgcalls AudioState 0 = muted; VideoState 2 = active.
  'remoteMedia' => EngineRemoteMedia(muted: e['audio'] == 0, videoOn: e['video'] == 2),
  'signaling' => EngineSignaling(e['data'] as Uint8List),
  'stopped' => EngineStopped(
    debugLog: e['debugLog'] as String? ?? '',
    ratingSuggested: e['ratingSuggested'] == true,
  ),
  _ => null,
};
