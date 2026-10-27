import 'dart:async';

import 'package:flutter/services.dart';

/// The phone's active connection, as Android reports it.
enum ConnectionType { none, wifi, mobile, roaming, other }

/// Watches the active connection (wifi, mobile, roaming).
abstract interface class NetworkMonitor {
  ConnectionType get current;
  Stream<ConnectionType> get changes;
  Future<void> start();
  void dispose();
}

/// [NetworkMonitor] over the native `dev.lumina/network` event channel
/// (ConnectivityManager's default network callback).
class PlatformNetworkMonitor implements NetworkMonitor {
  static const _channel = EventChannel('dev.lumina/network');

  final _changes = StreamController<ConnectionType>.broadcast();
  StreamSubscription<Object?>? _subscription;

  @override
  ConnectionType current = ConnectionType.other;

  @override
  Stream<ConnectionType> get changes => _changes.stream;

  @override
  Future<void> start() async {
    _subscription ??= _channel.receiveBroadcastStream().listen((event) {
      final type = ConnectionType.values.where((t) => t.name == event).firstOrNull ?? ConnectionType.other;
      if (type == current) return;
      current = type;
      _changes.add(type);
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _changes.close();
  }
}
