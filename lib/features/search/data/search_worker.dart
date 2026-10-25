import 'dart:async';
import 'dart:isolate';

import '../../../core/search/message_search.dart';
import 'search_db.dart';

/// Requests understood by the index isolate.
sealed class _Req {
  const _Req(this.id);
  final int id;
}

final class _Upsert extends _Req {
  const _Upsert(super.id, this.records);
  final List<List<Object>> records;
}

final class _Delete extends _Req {
  const _Delete(super.id, this.chatId, this.ids);
  final int chatId;
  final List<int> ids;
}

final class _Rename extends _Req {
  const _Rename(super.id, this.chatId, this.oldId, this.newId);
  final int chatId, oldId, newId;
}

final class _Search extends _Req {
  const _Search(super.id, this.query, this.chatId, this.limit);
  final String query;
  final int? chatId;
  final int limit;
}

final class _Stats extends _Req {
  const _Stats(super.id);
}

final class _GetProgress extends _Req {
  const _GetProgress(super.id, this.chatId);
  final int chatId;
}

final class _SetProgress extends _Req {
  const _SetProgress(super.id, this.chatId, this.oldestId, this.done);
  final int chatId, oldestId;
  final bool done;
}

final class _Clear extends _Req {
  const _Clear(super.id);
}

/// Owns the SQLite index on a background isolate so indexing bursts and
/// queries never touch the UI thread.
class SearchWorker {
  SearchWorker._(this._isolate, this._commands, this._responses);

  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _responses;
  final _pending = <int, Completer<Object?>>{};
  var _next = 1;

  static Future<SearchWorker> spawn(String path, String key) async {
    final responses = ReceivePort();
    final ready = Completer<SendPort>();
    late final SearchWorker worker;
    responses.listen((msg) {
      if (msg is SendPort) {
        ready.complete(msg);
      } else if (msg is (int, Object?)) {
        worker._pending.remove(msg.$1)?.complete(msg.$2);
      } else if (msg is (int, String, bool)) {
        // (id, error, isError)
        worker._pending.remove(msg.$1)?.completeError(StateError(msg.$2));
      }
    });
    final isolate = await Isolate.spawn(_main, (responses.sendPort, path, key), debugName: 'search-index');
    worker = SearchWorker._(isolate, await ready.future, responses);
    return worker;
  }

  Future<T> _ask<T>(_Req Function(int id) build) {
    final id = _next++;
    final c = _pending[id] = Completer<Object?>();
    _commands.send(build(id));
    return c.future.then((v) => v as T);
  }

  Future<void> upsert(List<IndexRecord> records) =>
      _ask<void>((id) => _Upsert(id, [for (final r in records) r.toList()]));

  Future<void> delete(int chatId, List<int> ids) => _ask<void>((id) => _Delete(id, chatId, ids));

  Future<void> rename(int chatId, int oldId, int newId) =>
      _ask<void>((id) => _Rename(id, chatId, oldId, newId));

  Future<List<MessageHit>> search(String q, {int? chatId, int limit = 100}) async {
    final raw = await _ask<List<Object?>>((id) => _Search(id, q, chatId, limit));
    return [
      for (final r in raw.cast<List<Object?>>())
        MessageHit(
          chatId: r[0]! as int,
          messageId: r[1]! as int,
          date: r[2]! as int,
          snippet: r[3]! as String,
        ),
    ];
  }

  Future<({int messages, int chats})> stats() async {
    final (m, c) = await _ask<(int, int)>((id) => _Stats(id));
    return (messages: m, chats: c);
  }

  Future<({int oldestId, bool done})?> progress(int chatId) async {
    final r = await _ask<(int, bool)?>((id) => _GetProgress(id, chatId));
    return r == null ? null : (oldestId: r.$1, done: r.$2);
  }

  Future<void> setProgress(int chatId, int oldestId, {required bool done}) =>
      _ask<void>((id) => _SetProgress(id, chatId, oldestId, done));

  Future<void> clear() => _ask<void>((id) => _Clear(id));

  void dispose() {
    _isolate.kill();
    _responses.close();
  }

  static void _main((SendPort, String, String) args) {
    final (reply, path, key) = args;
    final db = SearchDb.open(path, key: key);
    final commands = ReceivePort();
    reply.send(commands.sendPort);
    commands.listen((msg) {
      final req = msg as _Req;
      try {
        Object? result;
        switch (req) {
          case _Upsert(:final records):
            db.upsert([for (final r in records) IndexRecord.fromList(r)]);
          case _Delete(:final chatId, :final ids):
            db.delete(chatId, ids);
          case _Rename(:final chatId, :final oldId, :final newId):
            db.rename(chatId, oldId, newId);
          case _Search(:final query, :final chatId, :final limit):
            result = [
              for (final h in db.search(query, chatId: chatId, limit: limit))
                [h.chatId, h.messageId, h.date, h.snippet],
            ];
          case _Stats():
            final st = db.stats();
            result = (st.messages, st.chats);
          case _GetProgress(:final chatId):
            final p = db.progress(chatId);
            result = p == null ? null : (p.oldestId, p.done);
          case _SetProgress(:final chatId, :final oldestId, :final done):
            db.setProgress(chatId, oldestId, done: done);
          case _Clear():
            db.clear();
        }
        reply.send((req.id, result));
      } catch (e) {
        reply.send((req.id, '$e', true));
      }
    });
  }
}
