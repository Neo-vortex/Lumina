import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:lumina_tdlib/api.dart' as td;
import 'package:lumina_tdlib/client.dart';

import 'td_messages.dart';

/// How long one `td_receive` call may block while TDLib is idle. The receiver
/// yields to its event loop between calls, so this also bounds how long a
/// [StopReceiver] or [Ping] waits to be noticed.
const double _receiveTimeoutSeconds = 0.5;

/// Upper bound on objects drained into one [ReceivedBatch].
const int _maxBatch = 100;

/// Entry point of the receiver isolate.
///
/// `td_receive` is a blocking FFI call, so this isolate cannot service its own
/// event loop while waiting on TDLib. That is why sending lives in a separate
/// isolate ([senderMain]) instead of sharing this one.
Future<void> receiverMain(SendPort toUi) async {
  await TdPlugin.initialize();
  final plugin = TdPlugin.instance;

  final control = ReceivePort();
  var running = true;
  control.listen((message) {
    switch (message) {
      case Ping(:final id):
        toUi.send(Pong(id));
      case StopReceiver():
        running = false;
    }
  });
  toUi.send(ReceiverReady(control.sendPort));

  while (running) {
    final objects = <td.TdObject>[];
    final failures = <ParseFailure>[];

    var raw = plugin.tdReceive(_receiveTimeoutSeconds);
    while (raw != null) {
      _parse(raw, objects, failures);
      if (objects.length + failures.length >= _maxBatch) break;
      raw = plugin.tdReceive(0);
    }

    if (objects.isNotEmpty || failures.isNotEmpty) {
      toUi.send(ReceivedBatch(objects, failures));
    }
    // Let queued control messages run before blocking again.
    await Future<void>.delayed(Duration.zero);
  }

  control.close();
}

void _parse(String raw, List<td.TdObject> objects, List<ParseFailure> failures) {
  Map<String, dynamic>? map;
  try {
    map = jsonDecode(raw) as Map<String, dynamic>;
    final object = td.convertMapToObject(map);
    if (object != null) {
      objects.add(object);
      return;
    }
    failures.add(
      ParseFailure(
        type: map['@type'] as String?,
        error: 'No generated model for this type',
        extra: _asInt(map['@extra']),
        clientId: _asInt(map['@client_id']),
      ),
    );
  } catch (e) {
    failures.add(
      ParseFailure(
        type: map?['@type'] as String?,
        error: e.toString(),
        extra: _asInt(map?['@extra']),
        clientId: _asInt(map?['@client_id']),
      ),
    );
  }
}

int? _asInt(Object? value) => value is int ? value : null;

/// Entry point of the sender isolate: owns client creation, JSON encoding and
/// `td_send` / `td_execute`, keeping all of them off the UI isolate.
Future<void> senderMain(SendPort toUi) async {
  await TdPlugin.initialize();
  final plugin = TdPlugin.instance;

  final commands = ReceivePort();
  toUi.send(SenderReady(commands.sendPort));

  await for (final message in commands) {
    switch (message) {
      case CreateClientCommand():
        final id = plugin.tdCreateClientId();
        // A client only starts emitting updates after its first request.
        plugin.tdSend(id, jsonEncode(const td.GetOption(name: 'version').toJson()));
        toUi.send(ClientCreated(id));
      case SendCommand(:final clientId, :final extra, :final function):
        plugin.tdSend(clientId, jsonEncode(function.toJson(extra)));
      case ExecuteCommand(:final id, :final function):
        td.TdObject? result;
        try {
          result = td.convertJsonToObject(plugin.tdExecute(jsonEncode(function.toJson())));
        } catch (_) {
          result = null;
        }
        toUi.send(ExecuteResult(id, result));
    }
  }
}
