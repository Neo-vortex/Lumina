import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/search/data/fts_query.dart';
import 'package:lumina/features/search/data/search_db.dart';

IndexRecord rec(int id, String text, {int chat = 1, int date = 0}) =>
    IndexRecord(chatId: chat, messageId: id, date: date == 0 ? id : date, senderId: 7, text: text);

void main() {
  group('FtsQuery', () {
    test('long terms become quoted trigram phrases, short ones word prefixes', () {
      final q = FtsQuery.parse('meet at 5pm "office"');
      expect(q.trigram, '"meet" AND "5pm" AND "office"');
      expect(q.words, '"at"*');
    });

    test('quotes inside terms are escaped; punctuation is trimmed', () {
      expect(FtsQuery.parse('ab"cd').trigram, '"ab""cd"');
      expect(FtsQuery.parse('...hello!!!').trigram, '"hello"');
      expect(FtsQuery.parse('   ').isEmpty, isTrue);
    });
  });

  group('SearchDb (real SQLite FTS5)', () {
    late SearchDb db;
    setUp(() => db = SearchDb.memory());
    tearDown(() => db.close());

    test('substring matches inside words, case-insensitively', () {
      db.upsert([rec(1, 'The Quarterly Report is ready'), rec(2, 'see you tomorrow')]);
      final hits = db.search('arterl');
      expect(hits.map((h) => h.messageId), [1]);
      expect(hits.single.snippet, contains('[['));
    });

    test('CJK text without spaces is searchable', () {
      db.upsert([rec(1, '明天下午三点开会'), rec(2, '今天很好')]);
      expect(db.search('下午三点').map((h) => h.messageId), [1]);
    });

    test('all terms must match; short terms use prefixes', () {
      db.upsert([rec(1, 'meet at the office'), rec(2, 'meet me later'), rec(3, 'office party')]);
      expect(db.search('meet office').map((h) => h.messageId), [1]);
      expect(db.search('meet at').map((h) => h.messageId), [1]);
    });

    test('newest first, filterable by chat', () {
      db.upsert([
        rec(1, 'hello world', date: 10),
        rec(2, 'hello there', date: 30),
        rec(3, 'hello', chat: 2, date: 20),
      ]);
      expect(db.search('hello').map((h) => h.messageId), [2, 3, 1]);
      expect(db.search('hello', chatId: 2).map((h) => h.messageId), [3]);
    });

    test('edits re-index and deletes remove', () {
      db.upsert([rec(1, 'old text')]);
      db.upsert([rec(1, 'brand new words')]);
      expect(db.search('old'), isEmpty);
      expect(db.search('brand').map((h) => h.messageId), [1]);
      db.delete(1, [1]);
      expect(db.search('brand'), isEmpty);
      expect(db.stats().messages, 0);
    });

    test('pending ids are renamed to server ids', () {
      db.upsert([rec(100, 'pending hello')]);
      db.rename(1, 100, 200);
      expect(db.search('pending').single.messageId, 200);
    });

    test('backfill progress round-trips', () {
      expect(db.progress(5), isNull);
      db.setProgress(5, 1234, done: false);
      expect(db.progress(5), (oldestId: 1234, done: false));
      db.setProgress(5, 1, done: true);
      expect(db.progress(5)!.done, isTrue);
    });
  });
}
