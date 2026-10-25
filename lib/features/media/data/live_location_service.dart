import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/platform/system_channel.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../core/tdlib/td_client.dart';
import '../../../core/tdlib/td_errors.dart';

/// What the service needs from the device: a foreground service while
/// anything is shared (so updates continue with the app in the background)
/// and a fresh position fix.
abstract interface class LiveLocationPlatform {
  /// Starts the foreground service; with [ask], first asks for location
  /// (and notification) permission if needed. False without location access.
  Future<bool> begin({bool ask = true});

  Future<void> end();

  /// A fresh fix, never prompting. Null when unavailable.
  Future<td.Location?> position();
}

class SystemLiveLocationPlatform implements LiveLocationPlatform {
  const SystemLiveLocationPlatform([this._system = const SystemChannel()]);

  final SystemChannel _system;

  @override
  Future<bool> begin({bool ask = true}) => _system.liveLocationStart(ask: ask);

  @override
  Future<void> end() => _system.liveLocationStop();

  @override
  Future<td.Location?> position() async {
    final p = await _system.currentPosition();
    if (p == null) return null;
    return td.Location(latitude: p.latitude, longitude: p.longitude, horizontalAccuracy: p.accuracy);
  }
}

/// One live location message being kept up to date.
class LiveShare {
  LiveShare({required this.chatId, required this.messageId, required this.until, this.sent = false});

  final int chatId;

  /// Temporary until TDLib reports the send succeeded ([sent]).
  int messageId;
  bool sent;
  final DateTime until;
  td.Location? last;
  DateTime? lastAt;

  Map<String, Object> toJson() => {'chat': chatId, 'msg': messageId, 'until': until.millisecondsSinceEpoch};

  static LiveShare? fromJson(Object? j) {
    if (j is! Map) return null;
    final chat = j['chat'], msg = j['msg'], until = j['until'];
    if (chat is! int || msg is! int || until is! int) return null;
    return LiveShare(
      chatId: chat,
      messageId: msg,
      until: DateTime.fromMillisecondsSinceEpoch(until),
      sent: true,
    );
  }
}

/// Keeps outgoing live locations updated until they expire or are stopped
/// (from the bubble, or from another device: both arrive as the message's
/// `expiresIn` dropping to 0). Shares are saved so they resume after the
/// process is killed.
class LiveLocationService extends ChangeNotifier {
  LiveLocationService({
    required this._client,
    required this._prefs,
    this._platform = const SystemLiveLocationPlatform(),
    DateTime Function()? now,
    Duration interval = const Duration(seconds: 60),
  }) : _now = now ?? DateTime.now {
    _sub = _client.updates.listen(_onUpdate);
    _restore();
    if (interval > Duration.zero) _timer = Timer.periodic(interval, (_) => tick());
  }

  final TdClient _client;
  final AppPreferences _prefs;
  final LiveLocationPlatform _platform;
  final DateTime Function() _now;
  late final StreamSubscription<td.Update> _sub;
  Timer? _timer;
  final _shares = <LiveShare>[];
  var _running = false;
  var _ticking = false;

  /// Push when the position moved this far, or [refreshEvery] passed.
  static const minMoveMeters = 20.0;
  static const refreshEvery = Duration(minutes: 5);

  List<LiveShare> get shares => List.unmodifiable(_shares);

  /// Call before sending a live location: asks for permission and starts the
  /// foreground service. False when the user declined location access.
  Future<bool> prepare() async {
    final ok = await _platform.begin();
    _running = ok;
    if (ok && _shares.isEmpty) {
      // Nothing to keep alive if the send fails before [track].
      Timer(const Duration(seconds: 30), () {
        if (_shares.isEmpty) _stopPlatform();
      });
    }
    return ok;
  }

  /// Starts tracking the pending live location message TDLib just queued.
  void track(td.Message pending, int livePeriodSeconds) {
    _shares.add(
      LiveShare(
        chatId: pending.chatId,
        messageId: pending.id,
        until: _now().add(Duration(seconds: livePeriodSeconds)),
        sent: pending.sendingState == null,
      ),
    );
    if (!_running) {
      _running = true;
      _platform.begin(ask: false).ignore();
    }
    _save();
    notifyListeners();
  }

  @visibleForTesting
  Future<void> tick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      _dropExpired();
      final due = [
        for (final s in _shares)
          if (s.sent) s,
      ];
      if (due.isEmpty) return;
      final here = await _platform.position();
      if (here == null) return;
      final now = _now();
      for (final s in due) {
        final last = s.last;
        final moved = last == null || distanceMeters(last, here) >= minMoveMeters;
        final stale = s.lastAt == null || now.difference(s.lastAt!) >= refreshEvery;
        if (!moved && !stale) continue;
        try {
          // An edit carries the whole live location, so keep the message's own period.
          final sent = await _client.invoke<td.Message>(
            td.GetMessage(chatId: s.chatId, messageId: s.messageId),
          );
          final period = switch (sent.content) {
            td.MessageLiveLocation(:final location) => location.livePeriod,
            _ => null,
          };
          if (period == null) {
            _remove(s);
            continue;
          }
          await _client.invoke<td.Message>(
            td.EditMessageLiveLocation(
              chatId: s.chatId,
              messageId: s.messageId,
              location: td.LiveLocation(
                location: here,
                livePeriod: period,
                heading: 0,
                proximityAlertRadius: 0,
              ),
            ),
          );
          s
            ..last = here
            ..lastAt = now;
        } on TdException catch (e) {
          // The message is gone or can no longer be edited.
          if (e.code == 400) _remove(s);
        }
      }
    } finally {
      _ticking = false;
    }
  }

  void _onUpdate(td.Update u) {
    switch (u) {
      case td.UpdateMessageSendSucceeded(:final message, :final oldMessageId):
        final s = _find(message.chatId, oldMessageId);
        if (s == null) return;
        s
          ..messageId = message.id
          ..sent = true;
        _save();
        // Push a first fix soon after the send instead of waiting a minute.
        unawaited(tick());
      case td.UpdateMessageSendFailed(:final message, :final oldMessageId):
        final s = _find(message.chatId, oldMessageId);
        if (s != null) _remove(s);
      case td.UpdateMessageContent(:final chatId, :final messageId, :final newContent):
        final s = _find(chatId, messageId);
        if (s != null && newContent is td.MessageLiveLocation && newContent.expiresIn == 0) _remove(s);
      case td.UpdateDeleteMessages(:final chatId, :final messageIds, :final isPermanent) when isPermanent:
        for (final id in messageIds) {
          final s = _find(chatId, id);
          if (s != null) _remove(s);
        }
      case td.UpdateAuthorizationState(authorizationState: td.AuthorizationStateClosed()):
        _shares.clear();
        _save();
        _stopPlatform();
        notifyListeners();
      default:
    }
  }

  LiveShare? _find(int chatId, int messageId) {
    for (final s in _shares) {
      if (s.chatId == chatId && s.messageId == messageId) return s;
    }
    return null;
  }

  void _remove(LiveShare s) {
    _shares.remove(s);
    _save();
    if (_shares.isEmpty) _stopPlatform();
    notifyListeners();
  }

  void _dropExpired() {
    final now = _now();
    final expired = _shares.where((s) => !now.isBefore(s.until)).toList();
    expired.forEach(_remove);
  }

  void _stopPlatform() {
    if (!_running) return;
    _running = false;
    _platform.end().ignore();
  }

  void _restore() {
    try {
      final list = jsonDecode(_prefs.liveLocations) as List;
      final now = _now();
      _shares.addAll(list.map(LiveShare.fromJson).whereType<LiveShare>().where((s) => now.isBefore(s.until)));
    } catch (_) {}
    if (_shares.isNotEmpty) {
      _running = true;
      // No prompt at launch; without permission the ticks just get no fix.
      _platform.begin(ask: false).ignore();
    }
  }

  void _save() {
    _prefs.liveLocations = jsonEncode([
      for (final s in _shares)
        if (s.sent) s.toJson(),
    ]);
  }

  /// Great-circle distance (haversine).
  static double distanceMeters(td.Location a, td.Location b) {
    const r = 6371000.0;
    double rad(double d) => d * pi / 180;
    final dLat = rad(b.latitude - a.latitude);
    final dLon = rad(b.longitude - a.longitude);
    final h = pow(sin(dLat / 2), 2) + cos(rad(a.latitude)) * cos(rad(b.latitude)) * pow(sin(dLon / 2), 2);
    return 2 * r * asin(sqrt(h));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub.cancel();
    super.dispose();
  }
}
