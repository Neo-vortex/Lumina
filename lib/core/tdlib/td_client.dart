import 'package:lumina_tdlib/api.dart' as td;

/// The app's only view of TDLib. Everything above this layer depends on the
/// interface, so the `lumina_tdlib` bindings can be swapped (or faked in
/// tests) without touching features.
abstract interface class TdClient {
  /// TDLib updates (objects whose `extra` is null) for the live client.
  Stream<td.Update> get updates;

  /// Id of the live TDLib client, or null before [start] / after it closed.
  int? get clientId;

  /// Spawns the background isolates and creates the TDLib client.
  Future<void> start();

  /// Sends [function] and completes with its result.
  ///
  /// Throws [TdException] when TDLib answers with an `error`, and
  /// [TdTransportException] when no usable answer arrives.
  Future<T> invoke<T extends td.TdObject>(td.TdFunction function, {Duration? timeout});

  /// Runs one of TDLib's synchronous methods (e.g. `setLogVerbosityLevel`).
  Future<td.TdObject?> execute(td.TdFunction function);

  /// Drops the client after `authorizationStateClosed` and creates a fresh
  /// one. TDLib cannot reuse a closed client; this is the only path that
  /// creates a second client id in a process, and never while one is live.
  Future<void> recreateAfterClose();

  /// Confirms the receive loop is alive and restarts it if not.
  Future<void> ensureReceiving();

  Future<void> dispose();
}
