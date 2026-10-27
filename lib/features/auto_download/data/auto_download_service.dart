import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/storage/app_preferences.dart';
import '../../../core/tdlib/td_client.dart';
import '../../../core/telegram/telegram_cache.dart';
import '../../../core/telegram/auto_download_gate.dart';
import '../domain/auto_download_policy.dart';
import 'network_monitor.dart';

/// Settings → Data & storage → Auto-download: one [AutoDownloadPolicy] per
/// network type, kept in sync with TDLib, and the answer to "may this be
/// downloaded without asking?" for the network the phone is on now.
class AutoDownloadService implements AutoDownloadGate {
  AutoDownloadService({
    required TdClient client,
    required this._prefs,
    required this._cache,
    required NetworkMonitor network,
  }) : _client = client,
       _network = network {
    _auth = client.updates.listen((u) {
      if (u case td.UpdateAuthorizationState(authorizationState: td.AuthorizationStateReady())) {
        _ready = true;
        _syncAll().ignore();
        _sendNetworkType().ignore();
      } else if (u is td.UpdateAuthorizationState) {
        _ready = false;
      }
    });
    _networkChanges = network.changes.listen((_) {
      _changes.value++;
      if (_ready) _sendNetworkType().ignore();
    });
    network.start().ignore();
  }

  final TdClient _client;
  final AppPreferences _prefs;
  final TelegramCache _cache;
  final NetworkMonitor _network;
  late final StreamSubscription<td.Update> _auth;
  late final StreamSubscription<ConnectionType> _networkChanges;
  final _changes = ValueNotifier<int>(0);
  var _ready = false;
  td.AutoDownloadSettingsPresets? _serverPresets;

  /// Fires when a policy or the network changes.
  Listenable get changes => _changes;

  /// The network type the current connection counts as. Unknown or no
  /// connection counts as mobile, the cautious choice.
  NetworkKind get network => switch (_network.current) {
    ConnectionType.wifi || ConnectionType.other => NetworkKind.wifi,
    ConnectionType.roaming => NetworkKind.roaming,
    ConnectionType.mobile || ConnectionType.none => NetworkKind.mobile,
  };

  AutoDownloadPolicy policy(NetworkKind n) {
    final json = _prefs.autoDownloadPolicy(n.name);
    return (json == null ? null : AutoDownloadPolicy.fromJson(json)) ?? AutoDownloadPolicy.defaultFor(n);
  }

  Future<void> setPolicy(NetworkKind n, AutoDownloadPolicy p) async {
    _prefs.setAutoDownloadPolicy(n.name, p.toJson());
    _changes.value++;
    if (_ready) await _sync(n);
  }

  ChatKind chatKind(int chatId) => switch (_cache.chats[chatId]?.type) {
    td.ChatTypePrivate(:final userId) || td.ChatTypeSecret(:final userId) =>
      _cache.users[userId]?.isContact ?? false ? ChatKind.contacts : ChatKind.private,
    td.ChatTypeSupergroup(isChannel: true) => ChatKind.channels,
    td.ChatTypeSupergroup() || td.ChatTypeBasicGroup() => ChatKind.groups,
    null => ChatKind.private,
  };

  /// Whether [media] of [size] bytes in [chatId] downloads without a tap.
  @override
  bool allows({required int chatId, required MediaKind media, required int size}) =>
      policy(network).allows(media, chatKind(chatId), size: size);

  /// Whether the start of a video too large to auto-download is fetched.
  @override
  bool get preloadLargeVideos => policy(network).preloadLargeVideos;

  static td.NetworkType _tdType(NetworkKind n) => switch (n) {
    NetworkKind.mobile => const td.NetworkTypeMobile(),
    NetworkKind.wifi => const td.NetworkTypeWiFi(),
    NetworkKind.roaming => const td.NetworkTypeMobileRoaming(),
  };

  Future<void> _syncAll() async {
    for (final n in NetworkKind.values) {
      await _sync(n);
    }
  }

  Future<void> _sync(NetworkKind n) async {
    try {
      _serverPresets ??= await _client.invoke<td.AutoDownloadSettingsPresets>(
        const td.GetAutoDownloadSettingsPresets(),
      );
      final presets = _serverPresets!;
      // TDLib's own preset keeps the server's bitrate and preload choices.
      final base = switch (n) {
        NetworkKind.wifi => presets.high,
        NetworkKind.mobile => presets.medium,
        NetworkKind.roaming => presets.low,
      };
      final p = policy(n);
      // TDLib has one limit for everything but photos and videos.
      const small = [MediaKind.voice, MediaKind.videoMessages, MediaKind.gifs, MediaKind.music];
      final other = p.anyOn(MediaKind.files) ? p.maxFileSize : (small.any(p.anyOn) ? 10 * 1024 * 1024 : 0);
      await _client.invoke<td.Ok>(
        td.SetAutoDownloadSettings(
          type: _tdType(n),
          settings: base.copyWith(
            isAutoDownloadEnabled: p.enabled.isNotEmpty,
            maxPhotoFileSize: p.anyOn(MediaKind.photos) ? 10 * 1024 * 1024 : 0,
            maxVideoFileSize: p.anyOn(MediaKind.videos) ? p.maxVideoSize : 0,
            maxOtherFileSize: other,
            preloadLargeVideos: p.preloadLargeVideos,
          ),
        ),
      );
    } on Exception {
      // Best effort: the app's own downloads follow the policy regardless.
    }
  }

  Future<void> _sendNetworkType() async {
    final type = switch (_network.current) {
      ConnectionType.none => const td.NetworkTypeNone(),
      ConnectionType.wifi => const td.NetworkTypeWiFi(),
      ConnectionType.mobile => const td.NetworkTypeMobile(),
      ConnectionType.roaming => const td.NetworkTypeMobileRoaming(),
      ConnectionType.other => const td.NetworkTypeOther(),
    };
    try {
      await _client.invoke<td.Ok>(td.SetNetworkType(type: type));
    } on Exception {
      // TDLib falls back to its own detection.
    }
  }

  void dispose() {
    _auth.cancel();
    _networkChanges.cancel();
    _network.dispose();
    _changes.dispose();
  }
}
