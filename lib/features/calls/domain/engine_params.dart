import 'dart:convert';
import 'dart:typed_data';

import 'package:handy_tdlib_next/api.dart' as td;

/// Lowest call protocol layer the engine speaks (Telegram's CALL_MIN_LAYER).
const callMinLayer = 65;

/// The protocol Lumina offers in createCall / acceptCall.
td.CallProtocol callProtocol({required List<String> versions, required int maxLayer}) => td.CallProtocol(
  udpP2p: true,
  udpReflector: true,
  minLayer: callMinLayer,
  maxLayer: maxLayer,
  libraryVersions: versions,
);

/// A server the engine connects through.
class EngineEndpoint {
  const EngineEndpoint({
    required this.isRtc,
    required this.id,
    required this.ipv4,
    required this.ipv6,
    required this.port,
    required this.peerTag,
    required this.turn,
    required this.tcp,
    required this.reflectorId,
    required this.username,
    required this.password,
  });

  /// A WebRTC STUN/TURN server; otherwise a Telegram reflector.
  final bool isRtc;
  final int id;
  final String ipv4;
  final String ipv6;
  final int port;
  final Uint8List? peerTag;
  final bool turn;
  final bool tcp;

  /// 1-based index among reflectors ordered by id (0 for WebRTC servers),
  /// as Telegram's clients number them.
  final int reflectorId;
  final String username;
  final String password;

  Map<String, Object?> toMap() => {
    'isRtc': isRtc,
    'id': id,
    'ipv4': ipv4,
    'ipv6': ipv6,
    'port': port,
    'peerTag': peerTag,
    'turn': turn,
    'tcp': tcp,
    'reflectorId': reflectorId,
    'username': username,
    'password': password,
  };
}

/// SOCKS5 proxy for "Use proxy for calls".
class EngineProxy {
  const EngineProxy({required this.host, required this.port, this.login = '', this.password = ''});
  final String host;
  final int port;
  final String login;
  final String password;

  Map<String, Object?> toMap() => {'host': host, 'port': port, 'login': login, 'password': password};
}

/// Everything the engine needs to start a call (from CallStateReady).
class EngineParams {
  const EngineParams({
    required this.version,
    required this.endpoints,
    required this.encryptionKey,
    required this.outgoing,
    required this.allowP2p,
    required this.maxLayer,
    required this.customParameters,
    required this.initializationTimeout,
    required this.receiveTimeout,
    required this.enableAec,
    required this.enableNs,
    this.proxy,
    this.video = false,
  });

  /// tgcalls protocol version both sides agreed on.
  final String version;
  final List<EngineEndpoint> endpoints;
  final Uint8List encryptionKey;
  final bool outgoing;
  final bool allowP2p;
  final int maxLayer;
  final String customParameters;
  final double initializationTimeout;
  final double receiveTimeout;

  /// Software echo cancellation / noise suppression (off when the server
  /// config prefers the device's own).
  final bool enableAec;
  final bool enableNs;
  final EngineProxy? proxy;

  /// Start with the camera on.
  final bool video;

  Map<String, Object?> toMap() => {
    'version': version,
    'endpoints': [for (final e in endpoints) e.toMap()],
    'encryptionKey': encryptionKey,
    'outgoing': outgoing,
    'allowP2p': allowP2p,
    'maxLayer': maxLayer,
    'customParameters': customParameters,
    'initializationTimeout': initializationTimeout,
    'receiveTimeout': receiveTimeout,
    'enableAec': enableAec,
    'enableNs': enableNs,
    'proxy': proxy?.toMap(),
    'video': video,
  };
}

String _hex(Uint8List bytes) => [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

/// Maps TDLib's ready state to engine parameters, the way Telegram's
/// clients do. [proxy] is passed only when "Use proxy for calls" is on and
/// the active proxy is SOCKS5; P2P is then off so traffic stays proxied.
EngineParams engineParamsFor(
  td.Call call,
  td.CallStateReady ready, {
  required Duration connectTimeout,
  required Duration packetTimeout,
  bool deviceAec = false,
  bool deviceNs = false,
  EngineProxy? proxy,
}) {
  final reflectorIds = [
    for (final s in ready.servers)
      if (s.type is td.CallServerTypeTelegramReflector) s.id,
  ]..sort();
  final endpoints = <EngineEndpoint>[
    for (final s in ready.servers)
      switch (s.type) {
        td.CallServerTypeTelegramReflector(:final peerTag, :final isTcp) => () {
          final tag = peerTag.isEmpty ? null : base64Decode(peerTag);
          return EngineEndpoint(
            isRtc: false,
            id: s.id,
            ipv4: s.ipAddress,
            ipv6: s.ipv6Address,
            port: s.port,
            peerTag: tag,
            turn: false,
            tcp: isTcp,
            reflectorId: reflectorIds.indexOf(s.id) + 1,
            username: tag == null ? '' : 'reflector',
            password: tag == null ? '' : _hex(tag),
          );
        }(),
        td.CallServerTypeWebrtc(:final username, :final password, :final supportsTurn) => EngineEndpoint(
          isRtc: true,
          id: s.id,
          ipv4: s.ipAddress,
          ipv6: s.ipv6Address,
          port: s.port,
          peerTag: null,
          turn: supportsTurn,
          tcp: false,
          reflectorId: 0,
          username: username,
          password: password,
        ),
      },
  ];
  final server = _serverConfig(ready.config);
  return EngineParams(
    version: ready.protocol.libraryVersions.isEmpty ? '' : ready.protocol.libraryVersions.first,
    endpoints: endpoints,
    encryptionKey: base64Decode(ready.encryptionKey),
    outgoing: call.isOutgoing,
    allowP2p: ready.allowP2p && proxy == null,
    maxLayer: ready.protocol.maxLayer,
    customParameters: ready.customParameters,
    initializationTimeout: connectTimeout.inMilliseconds / 1000,
    receiveTimeout: packetTimeout.inMilliseconds / 1000,
    enableAec: !(deviceAec && server['use_system_aec'] == true),
    enableNs: !(deviceNs && server['use_system_ns'] == true),
    proxy: proxy,
    video: call.isVideo,
  );
}

Map<String, Object?> _serverConfig(String json) {
  try {
    final v = jsonDecode(json);
    return v is Map<String, Object?> ? v : const {};
  } catch (_) {
    return const {};
  }
}
