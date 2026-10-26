import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/display.dart';
import 'package:lumina_tdlib/api.dart' as td;

void main() {
  test('a minithumbnail decodes to the same bytes instance every build, so the image cache hits', () {
    const a = td.Minithumbnail(width: 40, height: 40, data: 'AQID');
    const b = td.Minithumbnail(width: 40, height: 40, data: 'AQID');
    final first = Display.minithumbnail(a);
    expect(first, [1, 2, 3]);
    expect(identical(Display.minithumbnail(a), first), isTrue);
    expect(identical(Display.minithumbnail(b), first), isTrue, reason: 'a fresh update carries a new object');
  });
}
