import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/folders/domain/addlist_link.dart';

void main() {
  test('reads the slug from every link form', () {
    for (final link in [
      'https://t.me/addlist/AbC_1-x',
      'http://telegram.me/addlist/AbC_1-x',
      't.me/addlist/AbC_1-x',
      'tg://addlist?slug=AbC_1-x',
      'tg:addlist?slug=AbC_1-x',
    ]) {
      expect(addlistSlug(link), 'AbC_1-x', reason: link);
    }
    expect(addlistSlug('https://t.me/proxy?server=a&port=1'), isNull);
    expect(addlistSlug('https://t.me/addlist/'), isNull);
  });

  test('finds addlist links in text and trims punctuation', () {
    expect(findAddlistLinks('Join t.me/addlist/AbC. Also tg://addlist?slug=XyZ, and t.me/addlist/AbC!'), [
      'https://t.me/addlist/AbC',
      'https://t.me/addlist/XyZ',
    ]);
    expect(findAddlistLinks('nothing'), isEmpty);
  });
}
