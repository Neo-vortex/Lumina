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

/// The system asked for something: accept, decline, hangup, hold, unhold
/// (Telecom, Bluetooth, a notification button) or open (notification tap).
final class EngineSystemAction extends EngineEvent {
  const EngineSystemAction(this.action);
  final String action;
}

/// Telecom wants Lumina's own ringing UI (self-managed incoming call).
final class EngineShowIncomingUi extends EngineEvent {
  const EngineShowIncomingUi();
}

/// The Phone app dialed [number] with Lumina's calling account.
final class EngineDialerCall extends EngineEvent {
  const EngineDialerCall(this.number);
  final String number;
}

/// Telecom changed the audio route: speaker, earpiece, bluetooth, headset.
final class EngineAudioRoute extends EngineEvent {
  const EngineAudioRoute(this.route);
  final String route;
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

/// The phone around a call: Telecom, notifications, ringing, the in-call
/// foreground service, audio route and permissions.
abstract interface class CallSystem {
  /// Registers Lumina with Telecom ([provider]: the Phone-app calling account
  /// too). False below Android 8, where only notifications are used.
  Future<bool> registerTelecom({required bool provider});

  /// True when the user enabled Lumina's calling account in the Phone app.
  Future<bool> callingAccountEnabled();
  Future<void> openCallingAccounts();

  /// False when Telecom refused; ring with [ring] instead.
  Future<bool> reportIncoming({
    required int callId,
    required String name,
    required bool video,
    required bool provider,
  });
  Future<bool> reportOutgoing({
    required int callId,
    required String name,
    required bool video,
    required bool provider,
  });

  /// dialing, ringing, active, held, ended (+ reason: local, remote,
  /// missed, rejected, busy, error).
  Future<void> setTelecomState(String state, {String? reason});

  Future<void> ring({required String name, required bool video});
  Future<void> stopRinging();
  Future<void> showOngoing({required String title, required String text, required bool video});
  Future<void> hideOngoing();
  Future<void> setSpeaker(bool on);

  /// A number the Phone app dialed before Dart was running.
  Future<String?> takeDialerCall();

  /// microphone, camera, notifications → granted.
  Future<Map<String, bool>> requestPermissions(List<String> names);
}

/// [CallEngine] and [CallSystem] over the "dev.lumina/calls" channels
/// (CallChannel.kt); permissions go through "dev.lumina/system".
class ChannelCallEngine implements CallEngine, CallSystem {
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

  static const _system = MethodChannel('dev.lumina/system');

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _methods.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> registerTelecom({required bool provider}) async =>
      await _call<bool>('telecomRegister', {'provider': provider}) ?? false;

  @override
  Future<bool> callingAccountEnabled() async => await _call<bool>('telecomProviderEnabled') ?? false;

  @override
  Future<void> openCallingAccounts() => _call('openCallingAccounts');

  @override
  Future<bool> reportIncoming({
    required int callId,
    required String name,
    required bool video,
    required bool provider,
  }) async =>
      await _call<bool>('telecomReportIncoming', {
        'callId': callId,
        'name': name,
        'video': video,
        'provider': provider,
      }) ??
      false;

  @override
  Future<bool> reportOutgoing({
    required int callId,
    required String name,
    required bool video,
    required bool provider,
  }) async =>
      await _call<bool>('telecomReportOutgoing', {
        'callId': callId,
        'name': name,
        'video': video,
        'provider': provider,
      }) ??
      false;

  @override
  Future<void> setTelecomState(String state, {String? reason}) =>
      _call('telecomState', {'state': state, 'reason': reason});

  @override
  Future<void> ring({required String name, required bool video}) =>
      _call('ring', {'title': name, 'video': video});

  @override
  Future<void> stopRinging() => _call('stopRinging');

  @override
  Future<void> showOngoing({required String title, required String text, required bool video}) =>
      _call('showOngoing', {'title': title, 'text': text, 'video': video});

  @override
  Future<void> hideOngoing() => _call('hideOngoing');

  @override
  Future<void> setSpeaker(bool on) => _call('setSpeaker', on);

  @override
  Future<String?> takeDialerCall() => _call<String>('takeDialerCall');

  @override
  Future<Map<String, bool>> requestPermissions(List<String> names) async {
    try {
      final r = await _system.invokeMapMethod<String, bool>('requestPermissions', names);
      return r ?? {for (final n in names) n: false};
    } on MissingPluginException {
      return {for (final n in names) n: false};
    }
  }
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
  'systemAction' => EngineSystemAction(e['action'] as String),
  'showIncomingUi' => const EngineShowIncomingUi(),
  'dialerCall' => EngineDialerCall(e['number'] as String),
  'audioRoute' => EngineAudioRoute(e['route'] as String),
  'stopped' => EngineStopped(
    debugLog: e['debugLog'] as String? ?? '',
    ratingSuggested: e['ratingSuggested'] == true,
  ),
  _ => null,
};
