import 'dart:async';

import 'package:lumina_tdlib/api.dart' as td;

import 'td_errors.dart';
import 'isolates/td_messages.dart';

/// Correlates invoke results with their callers through TDLib's `@extra`.
///
/// Pure Dart with no isolate or FFI dependency, so the routing rules are unit
/// testable on the host.
class InvokeRouter {
  int _nextExtra = 1;
  final _pending = <int, _Pending>{};

  int get pendingCount => _pending.length;

  /// Reserves an `extra` value and returns it with the future of its result.
  (int extra, Future<td.TdObject> result) register({Duration? timeout}) {
    final extra = _nextExtra++;
    final pending = _Pending(Completer<td.TdObject>());
    if (timeout != null) {
      pending.timer = Timer(timeout, () {
        if (_pending.remove(extra) != null) {
          pending.completer.completeError(TdTransportException('No answer within ${timeout.inSeconds}s'));
        }
      });
    }
    _pending[extra] = pending;
    return (extra, pending.completer.future);
  }

  /// Completes the caller waiting on [object]'s extra. Returns false when the
  /// object is not an answer to a pending invoke (i.e. it is an update).
  bool deliver(td.TdObject object) {
    final extra = object.extra;
    if (extra is! int) return false;
    final pending = _pending.remove(extra);
    if (pending == null) return false;
    pending.timer?.cancel();
    if (object is td.TdError) {
      pending.completer.completeError(TdException(object.code, object.message));
    } else {
      pending.completer.complete(object);
    }
    return true;
  }

  /// Fails the caller whose answer could not be parsed.
  void deliverFailure(ParseFailure failure) {
    final extra = failure.extra;
    if (extra == null) return;
    final pending = _pending.remove(extra);
    if (pending == null) return;
    pending.timer?.cancel();
    pending.completer.completeError(
      TdTransportException('Unparseable ${failure.type ?? 'response'}: ${failure.error}'),
    );
  }

  /// Fails every outstanding invoke, e.g. when the client closes.
  void failAll(String reason) {
    final all = _pending.values.toList();
    _pending.clear();
    for (final pending in all) {
      pending.timer?.cancel();
      pending.completer.completeError(TdTransportException(reason));
    }
  }
}

class _Pending {
  _Pending(this.completer);
  final Completer<td.TdObject> completer;
  Timer? timer;
}
