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

/// A video stream's frame size changed (remote / local), for layout.
final class EngineVideoSize extends EngineEvent {
  const EngineVideoSize({required this.remote, required this.width, required this.height});
  final bool remote;
  final int width;
  final int height;
}

final class EngineCameraSwitched extends EngineEvent {
  const EngineCameraSwitched({required this.front});
  final bool front;
}

/// Screen sharing ended ([byUser] false: the system or the user stopped it
/// from outside Lumina, e.g. the cast tile).
final class EngineScreenShareStopped extends EngineEvent {
  const EngineScreenShareStopped({required this.byUser});
  final bool byUser;
}

/// Where the camera bubble sits on a shared screen.
enum PipCorner { topLeft, topRight, bottomLeft, bottomRight }

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

  /// Flutter texture ids for the other side's video and our preview.
  Future<({int remote, int local})?> videoTextures();

  /// Camera on; false without permission or a running call.
  Future<bool> startVideo({required bool front});
  Future<void> stopVideo();
  Future<void> switchCamera({required bool front});

  /// After [CallSystem.requestScreenCapture]: shares the screen, with the
  /// camera bubble in [corner] when [camera].
  Future<bool> startScreenShare({required bool camera, required PipCorner corner});
  Future<void> stopScreenShare();
  Future<void> setPipCorner(PipCorner corner);

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

  /// The system's screen recording prompt. True when the user allowed it.
  Future<bool> requestScreenCapture();
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
  Future<({int remote, int local})?> videoTextures() async {
    try {
      final r = await _methods.invokeMapMethod<String, Object?>('videoTextures');
      if (r == null) return null;
      return (remote: (r['remote']! as num).toInt(), local: (r['local']! as num).toInt());
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> startVideo({required bool front}) async =>
      await _call<bool>('startVideo', {'front': front}) ?? false;

  @override
  Future<void> stopVideo() => _call('stopVideo');

  @override
  Future<void> switchCamera({required bool front}) => _call('switchCamera', front);

  @override
  Future<bool> startScreenShare({required bool camera, required PipCorner corner}) async =>
      await _call<bool>('startScreenShare', {'camera': camera, 'corner': corner.index}) ?? false;

  @override
  Future<void> stopScreenShare() => _call('stopScreenShare');

  @override
  Future<void> setPipCorner(PipCorner corner) => _call('setPipCorner', corner.index);

  @override
  Future<bool> requestScreenCapture() async {
    try {
      return await _system.invokeMethod<bool>('requestScreenCapture') ?? false;
    } on MissingPluginException {
      return false;
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
  'videoSize' => EngineVideoSize(
    remote: e['which'] == 'remote',
    width: (e['width'] as num).toInt(),
    height: (e['height'] as num).toInt(),
  ),
  'cameraSwitched' => EngineCameraSwitched(front: e['front'] == true),
  'screenShareStopped' => EngineScreenShareStopped(byUser: e['byUser'] == true),
  'stopped' => EngineStopped(
    debugLog: e['debugLog'] as String? ?? '',
    ratingSuggested: e['ratingSuggested'] == true,
  ),
  _ => null,
};
