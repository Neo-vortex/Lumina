import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

typedef _TdCreateClientIdNative = ffi.Int32 Function();
typedef _TdCreateClientId = int Function();
typedef _TdSendNative = ffi.Void Function(ffi.Int32, ffi.Pointer<Utf8>);
typedef _TdSend = void Function(int, ffi.Pointer<Utf8>);
typedef _TdReceiveNative = ffi.Pointer<Utf8> Function(ffi.Double);
typedef _TdReceive = ffi.Pointer<Utf8> Function(double);
typedef _TdExecuteNative = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
typedef _TdExecute = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);

/// The four functions of TDLib's JSON interface (td/telegram/td_json_client.h).
///
/// Every call blocks or allocates; keep them off the UI isolate.
class TdPlugin {
  TdPlugin(ffi.DynamicLibrary library) : _lookup = library.lookup;

  /// Opens [libPath] (default `libtdjson.so`, from the app's jniLibs) and sets [instance].
  static Future<void> initialize([String? libPath]) async {
    instance = TdPlugin(ffi.DynamicLibrary.open(libPath ?? 'libtdjson.so'));
  }

  /// The plugin opened by the latest [initialize] in this isolate.
  static late TdPlugin instance;

  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName) _lookup;

  late final _TdCreateClientId _createClientId =
      _lookup<ffi.NativeFunction<_TdCreateClientIdNative>>('td_create_client_id').asFunction();
  late final _TdSend _send = _lookup<ffi.NativeFunction<_TdSendNative>>('td_send').asFunction();
  late final _TdReceive _receive = _lookup<ffi.NativeFunction<_TdReceiveNative>>('td_receive').asFunction();
  late final _TdExecute _execute = _lookup<ffi.NativeFunction<_TdExecuteNative>>('td_execute').asFunction();

  /// A new client id; the client starts once it is sent its first request.
  int tdCreateClientId() => _createClientId();

  /// Sends a JSON request to [clientId]; the answer arrives via [tdReceive] with the same `@extra`.
  void tdSend(int clientId, String request) {
    final native = request.toNativeUtf8();
    try {
      _send(clientId, native);
    } finally {
      malloc.free(native);
    }
  }

  /// Next response or update for any client, or null after [timeout] seconds.
  ///
  /// The returned buffer belongs to TDLib and is valid until the next call, so it is copied here.
  String? tdReceive([double timeout = 1]) {
    final result = _receive(timeout);
    return result == ffi.nullptr ? null : result.toDartString();
  }

  /// Runs a synchronous TDLib method (e.g. `setLogVerbosityLevel`).
  String? tdExecute(String request) {
    final native = request.toNativeUtf8();
    try {
      final result = _execute(native);
      return result == ffi.nullptr ? null : result.toDartString();
    } finally {
      malloc.free(native);
    }
  }
}
