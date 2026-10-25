import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../core/tdlib/td_errors.dart';
import '../data/call_engine.dart';
import '../data/calls_repository.dart';
import '../domain/engine_params.dart';

part 'call_state.dart';

/// The one private call at a time: TDLib signaling (CallsRepository) on one
/// side, the native engine on the other, and the phone around it
/// ([CallSystem]: Telecom, ringing, the in-call service). App-wide, so a
/// call survives leaving the chat.
class CallCubit extends Cubit<CallState> {
  CallCubit({
    required this._repository,
    required this._engine,
    this._system,
    this._callProxy,
    String Function(int userId)? nameOf,
    bool Function()? useCallingAccount,
    DateTime Function()? now,
  }) : _nameOf = nameOf ?? ((id) => 'Call'),
       _useCallingAccount = useCallingAccount ?? (() => false),
       _now = now ?? DateTime.now,
       super(const CallState()) {
    _subs = [_repository.calls.listen(_onCall), _repository.signaling.listen(_onSignaling)];
    _init().ignore();
  }

  final CallsRepository _repository;
  final CallEngine _engine;
  final CallSystem? _system;
  final Future<EngineProxy?> Function()? _callProxy;
  final String Function(int userId) _nameOf;
  final bool Function() _useCallingAccount;
  final DateTime Function() _now;

  /// This side ended the call (for Telecom's disconnect cause).
  var _endedHere = false;

  /// Registers with Telecom and picks up a call the Phone app dialed while
  /// Lumina was starting.
  Future<void> _init() async {
    final system = _system;
    if (system == null || await _capabilities() == null) return;
    await system.registerTelecom(provider: _useCallingAccount());
    final number = await system.takeDialerCall();
    if (number != null) await _dialerCall(number);
  }

  /// Re-registers after the "calling account" setting changed.
  Future<void> refreshTelecom() async => _system?.registerTelecom(provider: _useCallingAccount());

  Future<bool> _permissions({required bool video}) async {
    final system = _system;
    if (system == null) return true;
    final granted = await system.requestPermissions(['microphone', 'notifications', if (video) 'camera']);
    return granted['microphone'] ?? false;
  }

  late final List<StreamSubscription<Object?>> _subs;

  /// Engine events, subscribed once the engine is known to exist.
  StreamSubscription<EngineEvent>? _engineSub;

  EngineCapabilities? _caps;
  int? _engineCallId;
  var _engineRunning = false;
  final _earlySignaling = <Uint8List>[];
  var _sendDebugInfo = false;

  Future<EngineCapabilities?> _capabilities() async {
    if (_caps != null) return _caps;
    if (!await _engine.available) return null;
    _engineSub ??= _engine.events.listen(_onEngine);
    return _caps = await _engine.capabilities();
  }

  Future<td.CallProtocol?> _protocol() async {
    final caps = await _capabilities();
    return caps == null ? null : callProtocol(versions: caps.versions, maxLayer: caps.maxLayer);
  }

  /// Calls [userId]. Returns an error to show, or null.
  Future<String?> startCall(int userId, {bool video = false, bool fromDialer = false}) async {
    if (state.inCall) return 'You are already in a call';
    final protocol = await _protocol();
    if (protocol == null) return 'Calls are not available in this build';
    if (!await _permissions(video: video)) return 'Lumina needs the microphone for calls';
    _endedHere = false;
    emit(CallState(phase: CallPhase.requesting, userId: userId, outgoing: true, video: video));
    try {
      final id = await _repository.create(userId, protocol, video: video);
      if (!fromDialer) {
        _system
            ?.reportOutgoing(callId: id, name: _nameOf(userId), video: video, provider: _useCallingAccount())
            .ignore();
      }
      return null;
    } on TdException catch (e) {
      emit(const CallState());
      if (fromDialer) _system?.setTelecomState('ended', reason: 'error').ignore();
      return e.message;
    }
  }

  /// A number dialed in the Phone app with Lumina's calling account.
  Future<void> _dialerCall(String number) async {
    final userId = await _repository.userIdByPhone(number);
    if (userId == null) {
      await _system?.setTelecomState('ended', reason: 'error');
      emit(const CallState(phase: CallPhase.ended, error: 'That number is not on Telegram'));
      return;
    }
    final error = await startCall(userId, fromDialer: true);
    if (error != null) await _system?.setTelecomState('ended', reason: 'error');
  }

  Future<String?> accept() async {
    final id = state.callId;
    if (id == null || state.phase != CallPhase.incoming) return null;
    await _system?.stopRinging();
    if (!await _permissions(video: state.video)) return 'Lumina needs the microphone for calls';
    final protocol = await _protocol();
    if (protocol == null) {
      await hangUp();
      return 'Calls are not available in this build';
    }
    emit(state.copyWith(phase: CallPhase.connecting));
    try {
      await _repository.accept(id, protocol);
      return null;
    } on TdException catch (e) {
      return e.message;
    }
  }

  /// Hangs up, declines an incoming call or cancels an outgoing one.
  Future<void> hangUp({bool disconnected = false}) async {
    final id = state.callId;
    if (id == null || !state.inCall) return;
    _endedHere = true;
    _system?.stopRinging().ignore();
    final connected = state.connectedAt;
    try {
      await _repository.discard(
        id,
        duration: connected == null ? Duration.zero : _now().difference(connected),
        video: state.video,
        disconnected: disconnected,
      );
    } on TdException {
      // The call may already be over on the server.
    }
  }

  Future<void> toggleMute() async {
    if (!state.inCall) return;
    final muted = !state.muted;
    emit(state.copyWith(muted: muted));
    if (_engineRunning) await _engine.setMuted(muted);
  }

  Future<void> toggleSpeaker() async {
    if (!state.inCall) return;
    final on = !state.speaker;
    emit(state.copyWith(speaker: on));
    await _system?.setSpeaker(on);
  }

  /// Stars 1–5 after a call TDLib asked to rate.
  Future<void> rate(int stars, {String comment = ''}) async {
    final id = state.callId;
    if (id == null) return;
    emit(state.copyWith(needRating: false));
    try {
      await _repository.rate(id, stars, comment: comment);
    } on TdException {
      // Rating is best effort.
    }
  }

  /// Clears an ended call from the screen.
  void dismiss() {
    if (state.phase == CallPhase.ended) emit(const CallState());
  }

  void _onCall(td.Call call) {
    final current = state.callId;
    if (current != null && current != call.id) {
      // A second incoming call while busy: decline it.
      if (!call.isOutgoing && call.state is td.CallStatePending && state.inCall) {
        _repository.discard(call.id, duration: Duration.zero, video: call.isVideo).ignore();
      }
      return;
    }
    if (current == null && state.phase != CallPhase.requesting && call.state is! td.CallStatePending) return;
    final base = state.copyWith(
      callId: call.id,
      userId: call.userId,
      outgoing: call.isOutgoing,
      video: call.isVideo,
    );
    final wasPhase = state.phase;
    switch (call.state) {
      case td.CallStatePending(:final isReceived):
        final incoming = !call.isOutgoing;
        emit(
          base.copyWith(
            phase: incoming ? CallPhase.incoming : CallPhase.outgoing,
            ringing: call.isOutgoing && isReceived,
          ),
        );
        if (incoming && wasPhase != CallPhase.incoming) _announceIncoming(call).ignore();
        if (!incoming && isReceived) _system?.setTelecomState('dialing').ignore();
      case td.CallStateExchangingKeys():
        emit(base.copyWith(phase: CallPhase.connecting));
      case final td.CallStateReady ready:
        emit(
          base.copyWith(
            phase: state.connectedAt == null ? CallPhase.connecting : state.phase,
            emojis: ready.emojis,
          ),
        );
        if (_engineCallId != call.id) _startEngine(call, ready).ignore();
      case td.CallStateHangingUp():
        emit(base.copyWith(phase: CallPhase.ending));
      case td.CallStateDiscarded(:final reason, :final needRating, :final needDebugInformation):
        _sendDebugInfo = needDebugInformation;
        _stopEngine();
        _endSystem(_telecomReason(reason, outgoing: call.isOutgoing));
        emit(base.copyWith(phase: CallPhase.ended, endReason: reason, needRating: needRating));
      case td.CallStateError(:final error):
        _stopEngine();
        _endSystem('error');
        emit(base.copyWith(phase: CallPhase.ended, error: error.message));
    }
  }

  /// Rings: through Telecom when it takes the call (it then asks for our UI,
  /// or the Phone app rings with the calling account), else our notification.
  Future<void> _announceIncoming(td.Call call) async {
    _endedHere = false;
    final system = _system;
    if (system == null) return;
    await _capabilities(); // Subscribes to Telecom events.
    final name = _nameOf(call.userId);
    final viaTelecom = await system.reportIncoming(
      callId: call.id,
      name: name,
      video: call.isVideo,
      provider: _useCallingAccount(),
    );
    if (!viaTelecom) await system.ring(name: name, video: call.isVideo);
  }

  String _telecomReason(td.CallDiscardReason reason, {required bool outgoing}) {
    if (_endedHere) return state.connectedAt == null && !outgoing ? 'rejected' : 'local';
    return switch (reason) {
      td.CallDiscardReasonMissed() => outgoing ? 'remote' : 'missed',
      td.CallDiscardReasonDeclined() => outgoing ? 'busy' : 'rejected',
      td.CallDiscardReasonDisconnected() => 'error',
      _ => 'remote',
    };
  }

  void _endSystem(String reason) {
    final system = _system;
    if (system == null) return;
    system.stopRinging().ignore();
    system.hideOngoing().ignore();
    system.setTelecomState('ended', reason: reason).ignore();
  }

  Future<void> _startEngine(td.Call call, td.CallStateReady ready) async {
    _engineCallId = call.id;
    final caps = await _capabilities();
    if (caps == null) {
      await hangUp();
      return;
    }
    final (timeouts, proxy) = await (_repository.timeouts(), _callProxy?.call() ?? Future.value()).wait;
    final params = engineParamsFor(
      call,
      ready,
      connectTimeout: timeouts.connect,
      packetTimeout: timeouts.packet,
      deviceAec: caps.deviceAec,
      deviceNs: caps.deviceNs,
      proxy: proxy,
    );
    if (state.callId != call.id || state.phase == CallPhase.ended) return;
    try {
      await _engine.start(params);
      _engineRunning = true;
      _system
          ?.showOngoing(
            title: _nameOf(call.userId),
            text: call.isVideo ? 'Video call' : 'Voice call',
            video: call.isVideo,
          )
          .ignore();
      if (state.muted) await _engine.setMuted(true);
      for (final data in _earlySignaling) {
        await _engine.receiveSignaling(data);
      }
      _earlySignaling.clear();
    } catch (e) {
      emit(state.copyWith(error: 'Could not start the call: $e'));
      await hangUp(disconnected: true);
    }
  }

  void _stopEngine() {
    _earlySignaling.clear();
    if (_engineRunning) {
      _engine.stop().ignore();
    } else {
      _engineCallId = null;
    }
  }

  void _onSignaling(({int callId, Uint8List data}) s) {
    if (s.callId != state.callId) return;
    if (_engineRunning) {
      _engine.receiveSignaling(s.data).ignore();
    } else {
      _earlySignaling.add(s.data);
    }
  }

  void _onEngine(EngineEvent e) {
    final id = state.callId;
    switch (e) {
      case EngineSignaling(:final data):
        if (id != null) _repository.sendSignaling(id, data).ignore();
      case EngineStateChanged(state: EngineConnection.established):
        emit(state.copyWith(phase: CallPhase.active, connectedAt: state.connectedAt ?? _now()));
        _system?.setTelecomState(state.held ? 'held' : 'active').ignore();
      case EngineStateChanged(state: EngineConnection.reconnecting):
        emit(state.copyWith(phase: CallPhase.reconnecting));
      case EngineStateChanged(state: EngineConnection.failed):
        hangUp(disconnected: true).ignore();
      case EngineStateChanged():
        break;
      case EngineSignalBars(:final bars):
        emit(state.copyWith(signalBars: bars));
      case EngineRemoteMedia(:final muted, :final videoOn):
        emit(state.copyWith(remoteMuted: muted, remoteVideo: videoOn));
      case EngineAudioLevels():
        break;
      case EngineSystemAction(:final action):
        _onSystemAction(action);
      case EngineShowIncomingUi():
        if (state.phase == CallPhase.incoming) {
          _system?.ring(name: _nameOf(state.userId ?? 0), video: state.video).ignore();
        }
      case EngineDialerCall(:final number):
        _dialerCall(number).ignore();
      case EngineAudioRoute(:final route):
        emit(state.copyWith(speaker: route == 'speaker'));
      case EngineStopped(:final debugLog):
        _engineRunning = false;
        _engineCallId = null;
        if (_sendDebugInfo && id != null && debugLog.isNotEmpty) {
          _repository.sendDebugInformation(id, debugLog).ignore();
        }
        _sendDebugInfo = false;
    }
  }

  void _onSystemAction(String action) {
    switch (action) {
      case 'accept':
        accept().ignore();
      case 'decline' || 'hangup':
        hangUp().ignore();
      case 'hold':
        // Another call took over: mute until resumed.
        emit(state.copyWith(held: true));
        if (_engineRunning) _engine.setMuted(true).ignore();
      case 'unhold':
        emit(state.copyWith(held: false));
        if (_engineRunning) _engine.setMuted(state.muted).ignore();
    }
  }

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _engineSub?.cancel();
    if (_engineRunning) await _engine.stop();
    return super.close();
  }
}
