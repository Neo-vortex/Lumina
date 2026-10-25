import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:lumina/features/calls/bloc/call_cubit.dart';
import 'package:lumina/features/calls/data/call_engine.dart';
import 'package:lumina/features/calls/data/calls_repository.dart';
import 'package:lumina/features/calls/domain/engine_params.dart';

import '../../helpers/fakes.dart';

class FakeEngine implements CallEngine {
  var isAvailable = true;
  final started = <EngineParams>[];
  final received = <Uint8List>[];
  final mutes = <bool>[];
  var stops = 0;
  final _events = StreamController<EngineEvent>.broadcast();

  void emit(EngineEvent e) => _events.add(e);

  @override
  Future<bool> get available async => isAvailable;

  @override
  Future<EngineCapabilities> capabilities() async =>
      (versions: const ['11.0.0', '9.0.0'], maxLayer: 92, deviceAec: true, deviceNs: false);

  @override
  Future<void> start(EngineParams params) async => started.add(params);

  @override
  Future<void> receiveSignaling(Uint8List data) async => received.add(data);

  @override
  Future<void> setMuted(bool muted) async => mutes.add(muted);

  @override
  Future<void> stop() async {
    stops++;
    emit(const EngineStopped(debugLog: '{"log":1}', ratingSuggested: false));
  }

  final video = <String>[];
  var screenCorner = PipCorner.bottomRight;

  @override
  Future<({int remote, int local})?> videoTextures() async => (remote: 11, local: 12);

  @override
  Future<bool> startVideo({required bool front}) async {
    video.add('start front=$front');
    return true;
  }

  @override
  Future<void> stopVideo() async => video.add('stop');

  @override
  Future<void> switchCamera({required bool front}) async => video.add('switch front=$front');

  @override
  Future<bool> startScreenShare({required bool camera, required PipCorner corner}) async {
    video.add('screen camera=$camera ${corner.name}');
    return true;
  }

  @override
  Future<void> stopScreenShare() async {
    video.add('stop screen');
    emit(const EngineScreenShareStopped(byUser: true));
  }

  @override
  Future<void> setPipCorner(PipCorner corner) async => screenCorner = corner;

  @override
  Stream<EngineEvent> get events => _events.stream;
}

final _key = base64Encode(List<int>.generate(256, (i) => i % 256));

td.CallStateReady ready({String config = '{}', bool allowP2p = true}) => td.CallStateReady(
  protocol: const td.CallProtocol(
    udpP2p: true,
    udpReflector: true,
    minLayer: 65,
    maxLayer: 92,
    libraryVersions: ['9.0.0'],
  ),
  servers: [
    td.CallServer(
      id: 900,
      ipAddress: '1.2.3.4',
      ipv6Address: '',
      port: 532,
      type: td.CallServerTypeTelegramReflector(peerTag: base64Encode([0xab, 0x01]), isTcp: false),
    ),
    const td.CallServer(
      id: 7,
      ipAddress: '5.6.7.8',
      ipv6Address: '::1',
      port: 3478,
      type: td.CallServerTypeWebrtc(username: 'u', password: 'p', supportsTurn: true, supportsStun: true),
    ),
    const td.CallServer(
      id: 100,
      ipAddress: '9.9.9.9',
      ipv6Address: '',
      port: 532,
      type: td.CallServerTypeTelegramReflector(peerTag: '', isTcp: true),
    ),
  ],
  config: config,
  encryptionKey: _key,
  emojis: const ['🐱', '🍕', '🚀', '🌙'],
  allowP2p: allowP2p,
  isGroupCallSupported: false,
  customParameters: '{"x":1}',
);

td.Call call(int id, td.CallState state, {bool outgoing = true, bool video = false}) =>
    td.Call(id: id, uniqueId: 0, userId: 42, isOutgoing: outgoing, isVideo: video, state: state);

void main() {
  systemTests();

  group('engine parameters', () {
    test('reflectors are numbered by id and authenticate with their peer tag', () {
      final p = engineParamsFor(
        call(1, ready()),
        ready(),
        connectTimeout: const Duration(seconds: 30),
        packetTimeout: const Duration(seconds: 10),
      );
      expect(p.version, '9.0.0');
      expect(p.encryptionKey, hasLength(256));
      final byId = {for (final e in p.endpoints) e.id: e};
      expect(byId[100]!.reflectorId, 1);
      expect(byId[900]!.reflectorId, 2);
      expect(byId[900]!.username, 'reflector');
      expect(byId[900]!.password, 'ab01');
      expect(byId[100]!.tcp, isTrue);
      expect(byId[100]!.username, '', reason: 'no peer tag');
      expect(byId[7]!.isRtc, isTrue);
      expect((byId[7]!.reflectorId, byId[7]!.turn, byId[7]!.username), (0, true, 'u'));
      expect((p.initializationTimeout, p.receiveTimeout), (30.0, 10.0));
      expect(p.customParameters, '{"x":1}');
    });

    test('device echo cancellation is used only when the server says so', () {
      EngineParams params(String config) => engineParamsFor(
        call(1, ready()),
        ready(config: config),
        connectTimeout: Duration.zero,
        packetTimeout: Duration.zero,
        deviceAec: true,
        deviceNs: true,
      );
      expect(params('{}').enableAec, isTrue);
      expect(params('{"use_system_aec":true,"use_system_ns":true}').enableAec, isFalse);
      expect(params('{"use_system_aec":true,"use_system_ns":true}').enableNs, isFalse);
      expect(params('not json').enableNs, isTrue);
    });

    test('a call proxy turns peer-to-peer off', () {
      final p = engineParamsFor(
        call(1, ready()),
        ready(),
        connectTimeout: Duration.zero,
        packetTimeout: Duration.zero,
        proxy: const EngineProxy(host: 'h', port: 1080),
      );
      expect(p.allowP2p, isFalse);
      expect(p.toMap()['proxy'], {'host': 'h', 'port': 1080, 'login': '', 'password': ''});
    });
  });

  test('engine events decode', () {
    expect(
      (parseEngineEvent({'type': 'state', 'value': 3}) as EngineStateChanged).state,
      EngineConnection.established,
    );
    final media = parseEngineEvent({'type': 'remoteMedia', 'audio': 0, 'video': 2}) as EngineRemoteMedia;
    expect((media.muted, media.videoOn), (true, true));
    expect(parseEngineEvent({'type': 'nope'}), isNull);
  });

  group('CallCubit', () {
    late FakeTdClient client;
    late FakeEngine engine;
    late CallCubit cubit;
    var now = DateTime(2026, 10, 25, 12);

    setUp(() {
      client = FakeTdClient()
        ..respond = (f) => switch (f) {
          td.CreateCall() => const td.CallId(id: 5),
          td.GetOption() => const td.OptionValueInteger(value: 20000),
          _ => const td.Ok(),
        };
      engine = FakeEngine();
      now = DateTime(2026, 10, 25, 12);
      cubit = CallCubit(repository: CallsRepository(client), engine: engine, now: () => now);
    });

    tearDown(() => cubit.close());

    Future<void> settle() =>
        Future<void>.delayed(Duration.zero).then((_) => Future<void>.delayed(Duration.zero));

    test('outgoing call: protocol, ringing, engine start, signaling both ways, hang up', () async {
      expect(await cubit.startCall(42), isNull);
      final create = client.sentOf<td.CreateCall>().single;
      expect(create.protocol.libraryVersions, ['11.0.0', '9.0.0']);
      expect((create.protocol.minLayer, create.protocol.maxLayer), (65, 92));

      client.emitUpdate(
        td.UpdateCall(call: call(5, const td.CallStatePending(isCreated: true, isReceived: true))),
      );
      await settle();
      expect(cubit.state.phase, CallPhase.outgoing);
      expect(cubit.state.ringing, isTrue);

      // Signaling can arrive before the engine is up.
      client.emitUpdate(td.UpdateNewCallSignalingData(callId: 5, data: base64Encode([1, 2])));
      client.emitUpdate(td.UpdateCall(call: call(5, ready())));
      await settle();
      expect(engine.started.single.initializationTimeout, 20.0);
      expect(engine.received.single, [1, 2]);
      expect(cubit.state.emojis, hasLength(4));

      engine.emit(EngineSignaling(Uint8List.fromList([9])));
      await settle();
      expect(base64Decode(client.sentOf<td.SendCallSignalingData>().single.data), [9]);

      engine.emit(const EngineStateChanged(EngineConnection.established));
      await settle();
      expect(cubit.state.phase, CallPhase.active);

      now = now.add(const Duration(seconds: 75));
      await cubit.hangUp();
      final discard = client.sentOf<td.DiscardCall>().single;
      expect((discard.callId, discard.duration, discard.isDisconnected), (5, 75, false));
    });

    test('incoming call: accept, then the server ends it and wants debug info and a rating', () async {
      client.emitUpdate(
        td.UpdateCall(
          call: call(8, const td.CallStatePending(isCreated: true, isReceived: true), outgoing: false),
        ),
      );
      await settle();
      expect(cubit.state.phase, CallPhase.incoming);
      await cubit.accept();
      expect(client.sentOf<td.AcceptCall>().single.callId, 8);

      client.emitUpdate(td.UpdateCall(call: call(8, ready(), outgoing: false)));
      await settle();
      expect(engine.started.single.outgoing, isFalse);

      client.emitUpdate(
        td.UpdateCall(
          call: call(
            8,
            const td.CallStateDiscarded(
              reason: td.CallDiscardReasonHungUp(),
              needRating: true,
              needDebugInformation: true,
              needLog: false,
            ),
            outgoing: false,
          ),
        ),
      );
      await settle();
      expect(engine.stops, 1);
      expect(cubit.state.phase, CallPhase.ended);
      expect(cubit.state.needRating, isTrue);
      expect(client.sentOf<td.SendCallDebugInformation>().single.debugInformation, '{"log":1}');

      await cubit.rate(5);
      expect(client.sentOf<td.SendCallRating>().single.rating, 5);
      cubit.dismiss();
      expect(cubit.state.phase, CallPhase.idle);
    });

    test('a second incoming call while busy is declined', () async {
      await cubit.startCall(42);
      client.emitUpdate(
        td.UpdateCall(call: call(5, const td.CallStatePending(isCreated: true, isReceived: false))),
      );
      client.emitUpdate(
        td.UpdateCall(
          call: call(9, const td.CallStatePending(isCreated: true, isReceived: true), outgoing: false),
        ),
      );
      await settle();
      expect(cubit.state.callId, 5);
      expect(client.sentOf<td.DiscardCall>().single.callId, 9);
    });

    test('mute is remembered before the engine starts and applied after', () async {
      await cubit.startCall(42);
      client.emitUpdate(
        td.UpdateCall(call: call(5, const td.CallStatePending(isCreated: true, isReceived: true))),
      );
      await settle();
      await cubit.toggleMute();
      expect(engine.mutes, isEmpty);
      client.emitUpdate(td.UpdateCall(call: call(5, ready())));
      await settle();
      expect(engine.mutes, [true]);
    });

    test('engine failure hangs up as disconnected', () async {
      await cubit.startCall(42);
      client.emitUpdate(td.UpdateCall(call: call(5, ready())));
      await settle();
      engine.emit(const EngineStateChanged(EngineConnection.failed));
      await settle();
      expect(client.sentOf<td.DiscardCall>().single.isDisconnected, isTrue);
    });

    test('without the engine, calling explains why', () async {
      engine.isAvailable = false;
      expect(await cubit.startCall(42), contains('not available'));
      expect(client.sentOf<td.CreateCall>(), isEmpty);
    });
  });
}

class FakeSystem implements CallSystem {
  final log = <String>[];
  var telecomTakesCalls = true;
  String? dialed;
  var micGranted = true;

  @override
  Future<bool> registerTelecom({required bool provider}) async {
    log.add('register provider=$provider');
    return true;
  }

  @override
  Future<bool> callingAccountEnabled() async => false;

  @override
  Future<void> openCallingAccounts() async {}

  @override
  Future<bool> reportIncoming({
    required int callId,
    required String name,
    required bool video,
    required bool provider,
  }) async {
    log.add('incoming $callId $name');
    return telecomTakesCalls;
  }

  @override
  Future<bool> reportOutgoing({
    required int callId,
    required String name,
    required bool video,
    required bool provider,
  }) async {
    log.add('outgoing $callId $name');
    return true;
  }

  @override
  Future<void> setTelecomState(String state, {String? reason}) async =>
      log.add(reason == null ? 'state $state' : 'state $state $reason');

  @override
  Future<void> ring({required String name, required bool video}) async => log.add('ring $name');

  @override
  Future<void> stopRinging() async => log.add('stopRinging');

  @override
  Future<void> showOngoing({required String title, required String text, required bool video}) async =>
      log.add('ongoing $title');

  @override
  Future<void> hideOngoing() async => log.add('hideOngoing');

  @override
  Future<void> setSpeaker(bool on) async => log.add('speaker $on');

  @override
  Future<String?> takeDialerCall() async {
    final d = dialed;
    dialed = null;
    return d;
  }

  var cameraGranted = true;
  var screenAllowed = true;

  @override
  Future<Map<String, bool>> requestPermissions(List<String> names) async => {
    for (final n in names)
      n: switch (n) {
        'microphone' => micGranted,
        'camera' => cameraGranted,
        _ => true,
      },
  };

  @override
  Future<bool> requestScreenCapture() async => screenAllowed;
}

void systemTests() {
  group('CallCubit with the phone system', () {
    late FakeTdClient client;
    late FakeEngine engine;
    late FakeSystem system;
    CallCubit? cubit;

    CallCubit make() => cubit = CallCubit(
      repository: CallsRepository(client),
      engine: engine,
      system: system,
      nameOf: (id) => 'Ana',
      useCallingAccount: () => false,
    );

    setUp(() {
      client = FakeTdClient()
        ..respond = (f) => switch (f) {
          td.CreateCall() => const td.CallId(id: 5),
          td.GetOption() => const td.OptionValueInteger(value: 20000),
          td.GetAuthorizationState() => const td.AuthorizationStateReady(),
          td.SearchUserByPhoneNumber() => fakeUser().copyWith(id: 42),
          _ => const td.Ok(),
        };
      engine = FakeEngine();
      system = FakeSystem();
    });

    tearDown(() => cubit?.close());

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('incoming calls go to Telecom; our ringer only when Telecom asks or refuses', () async {
      make();
      await settle();
      expect(system.log.first, 'register provider=false');
      client.emitUpdate(
        td.UpdateCall(
          call: call(8, const td.CallStatePending(isCreated: true, isReceived: true), outgoing: false),
        ),
      );
      await settle();
      expect(system.log, contains('incoming 8 Ana'));
      expect(system.log, isNot(contains('ring Ana')));
      engine.emit(const EngineShowIncomingUi());
      await settle();
      expect(system.log, contains('ring Ana'));

      // Answer from a Bluetooth headset / the notification.
      engine.emit(const EngineSystemAction('accept'));
      await settle();
      expect(client.sentOf<td.AcceptCall>(), hasLength(1));
      expect(system.log, contains('stopRinging'));
    });

    test('when Telecom refuses, the notification rings', () async {
      system.telecomTakesCalls = false;
      make();
      client.emitUpdate(
        td.UpdateCall(
          call: call(8, const td.CallStatePending(isCreated: true, isReceived: true), outgoing: false),
        ),
      );
      await settle();
      expect(system.log, contains('ring Ana'));
    });

    test('outgoing: reported to Telecom, ongoing service, active, local hang-up', () async {
      make();
      await cubit!.startCall(42);
      await settle();
      expect(system.log, contains('outgoing 5 Ana'));
      client.emitUpdate(td.UpdateCall(call: call(5, ready())));
      await settle();
      expect(system.log, contains('ongoing Ana'));
      engine.emit(const EngineStateChanged(EngineConnection.established));
      await settle();
      expect(system.log, contains('state active'));
      await cubit!.hangUp();
      client.emitUpdate(
        td.UpdateCall(
          call: call(
            5,
            const td.CallStateDiscarded(
              reason: td.CallDiscardReasonHungUp(),
              needRating: false,
              needDebugInformation: false,
              needLog: false,
            ),
          ),
        ),
      );
      await settle();
      expect(system.log, containsAll(['hideOngoing', 'state ended local']));
    });

    test('declining an incoming call tells Telecom it was rejected', () async {
      make();
      client.emitUpdate(
        td.UpdateCall(
          call: call(8, const td.CallStatePending(isCreated: true, isReceived: true), outgoing: false),
        ),
      );
      await settle();
      await cubit!.hangUp();
      client.emitUpdate(
        td.UpdateCall(
          call: call(
            8,
            const td.CallStateDiscarded(
              reason: td.CallDiscardReasonDeclined(),
              needRating: false,
              needDebugInformation: false,
              needLog: false,
            ),
            outgoing: false,
          ),
        ),
      );
      await settle();
      expect(system.log, contains('state ended rejected'));
    });

    test('a number dialed in the Phone app while Lumina was starting becomes a call', () async {
      system.dialed = '+1 (555) 010-0042';
      make();
      await settle();
      final search = client.sentOf<td.SearchUserByPhoneNumber>().single;
      expect(search.phoneNumber, '+15550100042');
      expect(client.sentOf<td.CreateCall>().single.userId, 42);
      expect(system.log.where((l) => l.startsWith('outgoing')), isEmpty, reason: 'connection exists');
    });

    test('a dialed number that is not on Telegram ends the Phone-app call', () async {
      client.respond = (f) => switch (f) {
        td.GetAuthorizationState() => const td.AuthorizationStateReady(),
        td.SearchUserByPhoneNumber() => const td.TdError(code: 404, message: 'USER_NOT_FOUND'),
        _ => const td.Ok(),
      };
      system.dialed = '+15550100000';
      make();
      await settle();
      expect(system.log, contains('state ended error'));
      expect(cubit!.state.error, contains('not on Telegram'));
    });

    test('hold mutes the engine; unhold restores the user\'s choice', () async {
      make();
      await cubit!.startCall(42);
      client.emitUpdate(td.UpdateCall(call: call(5, ready())));
      await settle();
      engine.emit(const EngineSystemAction('hold'));
      await settle();
      expect(cubit!.state.held, isTrue);
      expect(engine.mutes.last, isTrue);
      engine.emit(const EngineSystemAction('unhold'));
      await settle();
      expect(engine.mutes.last, isFalse);
    });

    Future<void> activeCall({bool video = false}) async {
      make();
      await cubit!.startCall(42, video: video);
      client.emitUpdate(td.UpdateCall(call: call(5, ready(), video: video)));
      await settle();
    }

    test('a video call starts with the front camera and gets the textures', () async {
      await activeCall(video: true);
      expect(engine.started.single.video, isTrue);
      expect(cubit!.state.camera, isTrue);
      expect(cubit!.state.textures, (remote: 11, local: 12));
    });

    test('camera on/off and flip during a voice call', () async {
      await activeCall();
      expect(cubit!.state.camera, isFalse);
      expect(await cubit!.toggleCamera(), isNull);
      expect(cubit!.state.camera, isTrue);
      await cubit!.switchCamera();
      expect(cubit!.state.frontCamera, isFalse);
      await cubit!.toggleCamera();
      expect(engine.video, ['start front=true', 'switch front=false', 'stop']);
    });

    test('no camera permission, no video', () async {
      system.cameraGranted = false;
      await activeCall();
      expect(await cubit!.toggleCamera(), contains('camera'));
      expect(engine.video, isEmpty);
    });

    test('screen sharing with the camera bubble in the chosen corner', () async {
      await activeCall();
      await cubit!.setPipCorner(PipCorner.topLeft);
      expect(await cubit!.startScreenShare(withCamera: true), isNull);
      expect(engine.video.last, 'screen camera=true topLeft');
      expect((cubit!.state.screenSharing, cubit!.state.screenWithCamera), (true, true));
      await cubit!.stopScreenShare();
      await settle();
      expect(cubit!.state.screenSharing, isFalse);
    });

    test('declining the screen recording prompt shares nothing', () async {
      system.screenAllowed = false;
      await activeCall();
      expect(await cubit!.startScreenShare(withCamera: false), isNull);
      expect(engine.video, isEmpty);
      expect(cubit!.state.screenSharing, isFalse);
    });

    test('sharing stopped from outside Lumina updates the state', () async {
      await activeCall();
      await cubit!.startScreenShare(withCamera: false);
      engine.emit(const EngineScreenShareStopped(byUser: false));
      await settle();
      expect(cubit!.state.screenSharing, isFalse);
    });

    test('no microphone, no call', () async {
      system.micGranted = false;
      make();
      expect(await cubit!.startCall(42), contains('microphone'));
      expect(client.sentOf<td.CreateCall>(), isEmpty);
    });
  });
}
