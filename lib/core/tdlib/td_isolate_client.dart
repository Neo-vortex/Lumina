import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import 'invoke_router.dart';
import 'td_client.dart';
import 'td_errors.dart';
import 'isolates/td_isolates.dart';
import 'isolates/td_messages.dart';

/// [TdClient] backed by two background isolates:
///
/// * receiver: blocking `td_receive` loop + `convertMapToObject`, batched to UI
/// * sender:   `td_create_client_id`, `jsonEncode`, `td_send`, `td_execute`
///
/// The UI isolate only sees typed objects and never touches FFI or TDLib JSON.
class TdIsolateClient implements TdClient {
  TdIsolateClient();

  final _router = InvokeRouter();
  final _updates = StreamController<td.Update>.broadcast();
  final _executes = <int, Completer<td.TdObject?>>{};
  final _pongs = <int, Completer<void>>{};
  var _nextId = 1;

  final _fromBackground = ReceivePort('td->ui');
  StreamSubscription<Object?>? _subscription;

  Isolate? _receiver;
  Isolate? _sender;
  RawReceivePort? _receiverExit;
  RawReceivePort? _senderExit;
  SendPort? _receiverControl;
  SendPort? _senderCommands;
  Completer<void>? _receiverReady;
  Completer<void>? _senderReady;

  int? _clientId;
  Completer<int>? _creating;
  // Batches that arrive while a client is being created may already carry
  // its first updates; hold them until its id is known.
  final _heldWhileCreating = <ReceivedBatch>[];
  final _retiredClientIds = <int>{};
  var _disposed = false;

  @override
  Stream<td.Update> get updates => _updates.stream;

  @override
  int? get clientId => _clientId;

  @override
  Future<void> start() async {
    if (_subscription != null) return;
    _subscription = _fromBackground.listen(_onBackgroundMessage);
    await Future.wait([_spawnReceiver(), _spawnSender()]);
    await _createClient();
  }

  Future<void> _spawnReceiver() async {
    _receiverReady = Completer<void>();
    _receiverExit?.close();
    final exit = _receiverExit = RawReceivePort();
    exit.handler = (_) {
      exit.close();
      if (_disposed || _receiverExit != exit) return;
      debugPrint('TDLib receiver isolate exited; respawning');
      _receiverControl = null;
      unawaited(_spawnReceiver());
    };
    _receiver = await Isolate.spawn(
      receiverMain,
      _fromBackground.sendPort,
      debugName: 'td-receiver',
      onExit: exit.sendPort,
      onError: _fromBackground.sendPort,
    );
    await _receiverReady!.future;
  }

  Future<void> _spawnSender() async {
    _senderReady = Completer<void>();
    _senderExit?.close();
    final exit = _senderExit = RawReceivePort();
    exit.handler = (_) {
      exit.close();
      if (_disposed || _senderExit != exit) return;
      debugPrint('TDLib sender isolate exited; respawning');
      _senderCommands = null;
      // Requests queued in the dead isolate are lost; fail their callers.
      // The native client id survives, so no new client is created.
      _router.failAll('TDLib sender isolate restarted');
      unawaited(_spawnSender());
    };
    _sender = await Isolate.spawn(
      senderMain,
      _fromBackground.sendPort,
      debugName: 'td-sender',
      onExit: exit.sendPort,
      onError: _fromBackground.sendPort,
    );
    await _senderReady!.future;
  }

  Future<void> _createClient() async {
    assert(_clientId == null, 'Only one live TDLib client per process');
    final creating = _creating = Completer<int>();
    _senderCommands!.send(const CreateClientCommand());
    _clientId = await creating.future;
    _creating = null;
    final held = List.of(_heldWhileCreating);
    _heldWhileCreating.clear();
    held.forEach(_dispatch);
  }

  void _onBackgroundMessage(Object? message) {
    switch (message) {
      case ReceivedBatch():
        if (_creating != null) {
          _heldWhileCreating.add(message);
        } else {
          _dispatch(message);
        }
      case ClientCreated(:final clientId):
        _creating?.complete(clientId);
      case SenderReady(:final commands):
        _senderCommands = commands;
        _senderReady?.complete();
      case ReceiverReady(:final control):
        _receiverControl = control;
        _receiverReady?.complete();
      case ExecuteResult(:final id, :final result):
        _executes.remove(id)?.complete(result);
      case Pong(:final id):
        _pongs.remove(id)?.complete();
      case List() when message.length == 2:
        // onError: [error, stackTrace] as strings.
        debugPrint('TDLib isolate error: ${message[0]}\n${message[1]}');
    }
  }

  void _dispatch(ReceivedBatch batch) {
    for (final object in batch.objects) {
      final owner = object.clientId;
      if (owner != null && (owner != _clientId || _retiredClientIds.contains(owner))) {
        continue; // late traffic from a closed client
      }
      if (_router.deliver(object)) continue;
      if (object is td.Update) _updates.add(object);
    }
    for (final failure in batch.failures) {
      if (failure.extra != null) {
        _router.deliverFailure(failure);
      } else {
        debugPrint('Dropped unparseable TDLib update ${failure.type}: ${failure.error}');
      }
    }
  }

  @override
  Future<T> invoke<T extends td.TdObject>(td.TdFunction function, {Duration? timeout}) async {
    final clientId = _clientId;
    final commands = _senderCommands;
    if (clientId == null || commands == null) {
      throw const TdTransportException('TDLib client is not running');
    }
    final (extra, result) = _router.register(timeout: timeout);
    commands.send(SendCommand(clientId, extra, function));
    final object = await result;
    if (object is T) return object;
    throw TdTransportException('Expected $T, got ${object.runtimeType}');
  }

  @override
  Future<td.TdObject?> execute(td.TdFunction function) {
    final commands = _senderCommands;
    if (commands == null) {
      return Future.error(const TdTransportException('TDLib sender is not running'));
    }
    final id = _nextId++;
    final completer = _executes[id] = Completer<td.TdObject?>();
    commands.send(ExecuteCommand(id, function));
    return completer.future;
  }

  @override
  Future<void> recreateAfterClose() async {
    final old = _clientId;
    if (old != null) _retiredClientIds.add(old);
    _clientId = null;
    _router.failAll('TDLib client closed');
    await _createClient();
  }

  @override
  Future<void> ensureReceiving() async {
    final control = _receiverControl;
    if (_disposed || control == null) return;
    final id = _nextId++;
    final pong = _pongs[id] = Completer<void>();
    control.send(Ping(id));
    try {
      await pong.future.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      _pongs.remove(id);
      debugPrint('TDLib receive loop unresponsive; restarting it');
      // td_receive must never run on two threads at once, and a kill cannot
      // interrupt the FFI call in progress. So only kill here; the exit
      // handler respawns once the old isolate has actually gone.
      _receiver?.kill(priority: Isolate.immediate);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _receiverExit?.close();
    _senderExit?.close();
    _receiverControl?.send(const StopReceiver());
    _sender?.kill();
    _router.failAll('TDLib client disposed');
    await _subscription?.cancel();
    _fromBackground.close();
    await _updates.close();
  }
}
