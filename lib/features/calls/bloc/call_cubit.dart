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
/// side, the native engine on the other. App-wide, so a call survives
/// leaving the chat.
class CallCubit extends Cubit<CallState> {
  CallCubit({required this._repository, required this._engine, this._callProxy, DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(const CallState()) {
    _subs = [_repository.calls.listen(_onCall), _repository.signaling.listen(_onSignaling)];
  }

  final CallsRepository _repository;
  final CallEngine _engine;
  final Future<EngineProxy?> Function()? _callProxy;
  final DateTime Function() _now;
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
  Future<String?> startCall(int userId, {bool video = false}) async {
    if (state.inCall) return 'You are already in a call';
    final protocol = await _protocol();
    if (protocol == null) return 'Calls are not available in this build';
    emit(CallState(phase: CallPhase.requesting, userId: userId, outgoing: true, video: video));
    try {
      await _repository.create(userId, protocol, video: video);
      return null;
    } on TdException catch (e) {
      emit(const CallState());
      return e.message;
    }
  }

  Future<String?> accept() async {
    final id = state.callId;
    if (id == null || state.phase != CallPhase.incoming) return null;
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
    switch (call.state) {
      case td.CallStatePending(:final isReceived):
        emit(
          base.copyWith(
            phase: call.isOutgoing ? CallPhase.outgoing : CallPhase.incoming,
            ringing: call.isOutgoing && isReceived,
          ),
        );
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
        emit(base.copyWith(phase: CallPhase.ended, endReason: reason, needRating: needRating));
      case td.CallStateError(:final error):
        _stopEngine();
        emit(base.copyWith(phase: CallPhase.ended, error: error.message));
    }
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
      case EngineStopped(:final debugLog):
        _engineRunning = false;
        _engineCallId = null;
        if (_sendDebugInfo && id != null && debugLog.isNotEmpty) {
          _repository.sendDebugInformation(id, debugLog).ignore();
        }
        _sendDebugInfo = false;
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
