import 'package:sqlite3/sqlite3.dart';

import '../../../core/search/message_search.dart';
import 'fts_query.dart';

/// One message's searchable text.
class IndexRecord {
  const IndexRecord({
    required this.chatId,
    required this.messageId,
    required this.date,
    required this.senderId,
    required this.text,
  });

  final int chatId;
  final int messageId;
  final int date;
  final int senderId;
  final String text;

  List<Object> toList() => [chatId, messageId, date, senderId, text];

  static IndexRecord fromList(List<Object?> l) => IndexRecord(
    chatId: l[0]! as int,
    messageId: l[1]! as int,
    date: l[2]! as int,
    senderId: l[3]! as int,
    text: l[4]! as String,
  );
}

/// The full-text index: a content table plus two external-content FTS5
/// tables kept in sync by triggers. Synchronous; runs inside the worker
/// isolate (and directly in tests).
class SearchDb {
  SearchDb._(this._db);

  final Database _db;

  /// Opens (and creates) the index. [key] encrypts it when the SQLite build
  /// supports it (SQLite3MultipleCiphers on device).
  static SearchDb open(String path, {String? key}) {
    final db = sqlite3.open(path);
    if (key != null) db.execute("PRAGMA key = '${key.replaceAll("'", "''")}'");
    db
      ..execute('PRAGMA journal_mode = WAL')
      ..execute('PRAGMA synchronous = NORMAL');
    final s = SearchDb._(db).._migrate();
    return s;
  }

  static SearchDb memory() => SearchDb._(sqlite3.openInMemory()).._migrate();

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS msg(
        rowid INTEGER PRIMARY KEY,
        chat_id INTEGER NOT NULL,
        message_id INTEGER NOT NULL,
        date INTEGER NOT NULL,
        sender_id INTEGER NOT NULL,
        text TEXT NOT NULL,
        UNIQUE(chat_id, message_id)
      );
      CREATE INDEX IF NOT EXISTS msg_chat_date ON msg(chat_id, date);
      CREATE TABLE IF NOT EXISTS backfill(
        chat_id INTEGER PRIMARY KEY,
        oldest_id INTEGER NOT NULL,
        done INTEGER NOT NULL DEFAULT 0
      );
    ''');
    // Trigram with diacritic folding needs SQLite ≥ 3.45; fall back if older.
    try {
      _db.execute(
        "CREATE VIRTUAL TABLE IF NOT EXISTS msg_tri USING fts5(text, content='msg', content_rowid='rowid', "
        "tokenize='trigram remove_diacritics 1')",
      );
    } on SqliteException {
      _db.execute(
        "CREATE VIRTUAL TABLE IF NOT EXISTS msg_tri USING fts5(text, content='msg', content_rowid='rowid', tokenize='trigram')",
      );
    }
    _db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS msg_words USING fts5(
        text, content='msg', content_rowid='rowid', tokenize='unicode61 remove_diacritics 2'
      );
      CREATE TRIGGER IF NOT EXISTS msg_ai AFTER INSERT ON msg BEGIN
        INSERT INTO msg_tri(rowid, text) VALUES (new.rowid, new.text);
        INSERT INTO msg_words(rowid, text) VALUES (new.rowid, new.text);
      END;
      CREATE TRIGGER IF NOT EXISTS msg_ad AFTER DELETE ON msg BEGIN
        INSERT INTO msg_tri(msg_tri, rowid, text) VALUES ('delete', old.rowid, old.text);
        INSERT INTO msg_words(msg_words, rowid, text) VALUES ('delete', old.rowid, old.text);
      END;
      CREATE TRIGGER IF NOT EXISTS msg_au AFTER UPDATE OF text ON msg BEGIN
        INSERT INTO msg_tri(msg_tri, rowid, text) VALUES ('delete', old.rowid, old.text);
        INSERT INTO msg_words(msg_words, rowid, text) VALUES ('delete', old.rowid, old.text);
        INSERT INTO msg_tri(rowid, text) VALUES (new.rowid, new.text);
        INSERT INTO msg_words(rowid, text) VALUES (new.rowid, new.text);
      END;
    ''');
  }

  void upsert(List<IndexRecord> records) {
    if (records.isEmpty) return;
    final stmt = _db.prepare('''
      INSERT INTO msg(chat_id, message_id, date, sender_id, text) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(chat_id, message_id) DO UPDATE SET text = excluded.text, date = excluded.date
      WHERE msg.text <> excluded.text
    ''');
    _db.execute('BEGIN');
    try {
      for (final r in records) {
        if (r.text.trim().isEmpty) continue;
        stmt.execute(r.toList());
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    } finally {
      stmt.close();
    }
  }

  void delete(int chatId, List<int> messageIds) {
    if (messageIds.isEmpty) return;
    final stmt = _db.prepare('DELETE FROM msg WHERE chat_id = ? AND message_id = ?');
    _db.execute('BEGIN');
    for (final id in messageIds) {
      stmt.execute([chatId, id]);
    }
    _db.execute('COMMIT');
    stmt.close();
  }

  /// Replaces a pending message id with its final server id.
  void rename(int chatId, int oldId, int newId) => _db.execute(
    'UPDATE OR REPLACE msg SET message_id = ? WHERE chat_id = ? AND message_id = ?',
    [newId, chatId, oldId],
  );

  List<MessageHit> search(String input, {int? chatId, int limit = 100}) {
    final q = FtsQuery.parse(input);
    if (q.isEmpty) return const [];
    final where = <String>[];
    final args = <Object>[];
    String snippetTable;
    String from;
    if (q.trigram != null) {
      from = 'msg_tri JOIN msg m ON m.rowid = msg_tri.rowid';
      where.add('msg_tri MATCH ?');
      args.add(q.trigram!);
      snippetTable = 'msg_tri';
      if (q.words != null) {
        where.add('m.rowid IN (SELECT rowid FROM msg_words WHERE msg_words MATCH ?)');
        args.add(q.words!);
      }
    } else {
      from = 'msg_words JOIN msg m ON m.rowid = msg_words.rowid';
      where.add('msg_words MATCH ?');
      args.add(q.words!);
      snippetTable = 'msg_words';
    }
    if (chatId != null) {
      where.add('m.chat_id = ?');
      args.add(chatId);
    }
    args.add(limit);
    final rows = _db.select(
      "SELECT m.chat_id, m.message_id, m.date, snippet($snippetTable, 0, '[[', ']]', '…', 14) AS snip "
      'FROM $from WHERE ${where.join(' AND ')} ORDER BY m.date DESC LIMIT ?',
      args,
    );
    return [
      for (final r in rows)
        MessageHit(
          chatId: r['chat_id'] as int,
          messageId: r['message_id'] as int,
          date: r['date'] as int,
          snippet: r['snip'] as String,
        ),
    ];
  }

  ({int messages, int chats}) stats() {
    final r = _db.select('SELECT COUNT(*) AS n, COUNT(DISTINCT chat_id) AS c FROM msg').first;
    return (messages: r['n'] as int, chats: r['c'] as int);
  }

  /// Backfill cursor per chat: oldest message id indexed, and whether the
  /// start of the history was reached.
  ({int oldestId, bool done})? progress(int chatId) {
    final rows = _db.select('SELECT oldest_id, done FROM backfill WHERE chat_id = ?', [chatId]);
    if (rows.isEmpty) return null;
    return (oldestId: rows.first['oldest_id'] as int, done: (rows.first['done'] as int) == 1);
  }

  void setProgress(int chatId, int oldestId, {required bool done}) => _db.execute(
    'INSERT INTO backfill(chat_id, oldest_id, done) VALUES (?, ?, ?) '
    'ON CONFLICT(chat_id) DO UPDATE SET oldest_id = excluded.oldest_id, done = excluded.done',
    [chatId, oldestId, done ? 1 : 0],
  );

  void clear() => _db.execute('DELETE FROM msg; DELETE FROM backfill;');

  void close() => _db.close();
}
