import 'dart:isolate';

import 'package:lumina_tdlib/api.dart' as td;

// Messages exchanged between the UI isolate and the two TDLib isolates.
// Everything here must be sendable through a SendPort: plain immutable data,
// generated TDLib models, and SendPorts.

/// Sender isolate -> UI: the sender's command port is ready.
final class SenderReady {
  const SenderReady(this.commands);
  final SendPort commands;
}

/// UI -> sender: create the (single) TDLib client for this process.
final class CreateClientCommand {
  const CreateClientCommand();
}

/// Sender -> UI: the client id produced by `td_create_client_id`.
final class ClientCreated {
  const ClientCreated(this.clientId);
  final int clientId;
}

/// UI -> sender: encode [function] with [extra] and `td_send` it.
final class SendCommand {
  const SendCommand(this.clientId, this.extra, this.function);
  final int clientId;
  final int extra;
  final td.TdFunction function;
}

/// UI -> sender: run [function] synchronously through `td_execute`.
final class ExecuteCommand {
  const ExecuteCommand(this.id, this.function);
  final int id;
  final td.TdFunction function;
}

/// Sender -> UI: result of an [ExecuteCommand].
final class ExecuteResult {
  const ExecuteResult(this.id, this.result);
  final int id;
  final td.TdObject? result;
}

/// Receiver isolate -> UI: the receiver's control port is ready.
final class ReceiverReady {
  const ReceiverReady(this.control);
  final SendPort control;
}

/// UI -> receiver: liveness probe; the receiver answers with [Pong].
final class Ping {
  const Ping(this.id);
  final int id;
}

final class Pong {
  const Pong(this.id);
  final int id;
}

/// UI -> receiver: leave the receive loop and exit.
final class StopReceiver {
  const StopReceiver();
}

/// Receiver -> UI: objects parsed from consecutive `td_receive` calls.
/// Batched so a burst of updates costs one port message instead of hundreds.
final class ReceivedBatch {
  const ReceivedBatch(this.objects, this.failures);
  final List<td.TdObject> objects;
  final List<ParseFailure> failures;
}

/// A TDLib payload the generated models could not represent.
/// When it answered an invoke ([extra] != null) the waiting caller must be
/// failed instead of being left to hang.
final class ParseFailure {
  const ParseFailure({required this.type, required this.error, this.extra, this.clientId});
  final String? type;
  final String error;
  final int? extra;
  final int? clientId;
}
