import 'dart:convert';
import 'dart:typed_data';

import 'package:handy_tdlib_next/api.dart' as td;

import '../../../core/tdlib/td_client.dart';

/// TDLib's side of private calls: signaling only. The media runs in the
/// native engine (CallEngine).
class CallsRepository {
  CallsRepository(this._client);

  final TdClient _client;

  Stream<td.Call> get calls =>
      _client.updates.where((u) => u is td.UpdateCall).map((u) => (u as td.UpdateCall).call);

  /// Signaling data from the other side, per call id.
  Stream<({int callId, Uint8List data})> get signaling => _client.updates
      .where((u) => u is td.UpdateNewCallSignalingData)
      .map((u) => u as td.UpdateNewCallSignalingData)
      .map((u) => (callId: u.callId, data: base64Decode(u.data)));

  Future<int> create(int userId, td.CallProtocol protocol, {required bool video}) async {
    final id = await _client.invoke<td.CallId>(
      td.CreateCall(userId: userId, protocol: protocol, isVideo: video),
    );
    return id.id;
  }

  Future<void> accept(int callId, td.CallProtocol protocol) =>
      _client.invoke<td.Ok>(td.AcceptCall(callId: callId, protocol: protocol));

  /// Hangs up or declines. [disconnected] when the connection failed.
  Future<void> discard(
    int callId, {
    required Duration duration,
    required bool video,
    bool disconnected = false,
  }) => _client.invoke<td.Ok>(
    td.DiscardCall(
      callId: callId,
      isDisconnected: disconnected,
      duration: duration.inSeconds,
      isVideo: video,
      connectionId: 0,
    ),
  );

  Future<void> sendSignaling(int callId, Uint8List data) =>
      _client.invoke<td.Ok>(td.SendCallSignalingData(callId: callId, data: base64Encode(data)));

  Future<void> sendDebugInformation(int callId, String info) =>
      _client.invoke<td.Ok>(td.SendCallDebugInformation(callId: callId, debugInformation: info));

  Future<void> rate(
    int callId,
    int rating, {
    String comment = '',
    List<td.CallProblem> problems = const [],
  }) => _client.invoke<td.Ok>(
    td.SendCallRating(callId: callId, rating: rating, comment: comment, problems: problems),
  );

  /// The Telegram user with this phone number (dialed in the Phone app), or
  /// null. Waits up to [wait] for TDLib to be logged in, since a dialer
  /// call can start Lumina from cold.
  Future<int?> userIdByPhone(String number, {Duration wait = const Duration(seconds: 30)}) async {
    final digits = number.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return null;
    final deadline = DateTime.now().add(wait);
    while (true) {
      try {
        final state = await _client.invoke<td.AuthorizationState>(const td.GetAuthorizationState());
        if (state is td.AuthorizationStateReady) break;
        if (state is td.AuthorizationStateWaitPhoneNumber || state is td.AuthorizationStateClosed) {
          return null;
        }
      } catch (_) {}
      if (DateTime.now().isAfter(deadline)) return null;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    try {
      final user = await _client.invoke<td.User>(
        td.SearchUserByPhoneNumber(phoneNumber: digits, onlyLocal: false),
      );
      return user.id;
    } catch (_) {
      return null;
    }
  }

  /// Server timeouts for the engine (TDLib options, with Telegram's
  /// defaults when missing).
  Future<({Duration connect, Duration packet})> timeouts() async {
    Future<int?> option(String name) async {
      try {
        final v = await _client.invoke<td.OptionValue>(td.GetOption(name: name));
        return v is td.OptionValueInteger ? v.value : null;
      } catch (_) {
        return null;
      }
    }

    final (connect, packet) = await (
      option('call_connect_timeout_ms'),
      option('call_packet_timeout_ms'),
    ).wait;
    return (
      connect: Duration(milliseconds: connect ?? 30000),
      packet: Duration(milliseconds: packet ?? 10000),
    );
  }
}
