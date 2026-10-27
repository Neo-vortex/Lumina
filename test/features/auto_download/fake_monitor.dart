import 'dart:async';

import 'package:lumina/features/auto_download/data/network_monitor.dart';

class FakeMonitor implements NetworkMonitor {
  final _changes = StreamController<ConnectionType>.broadcast(sync: true);
  @override
  ConnectionType current = ConnectionType.wifi;

  void change(ConnectionType t) {
    current = t;
    _changes.add(t);
  }

  @override
  Stream<ConnectionType> get changes => _changes.stream;

  @override
  Future<void> start() async {}

  @override
  void dispose() {}
}
