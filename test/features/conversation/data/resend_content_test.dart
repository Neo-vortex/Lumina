import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:lumina/features/conversation/data/resend_content.dart';

import '../../../helpers/fakes.dart';

void main() {
  test('text goes out again as the same text', () {
    final c = resendContent(fakeMessage(1, outgoing: true, text: 'hello'));
    expect(c, isA<td.InputMessageText>());
    expect((c! as td.InputMessageText).text.text, 'hello');
  });

  test('content it cannot rebuild gives null', () {
    final m = fakeMessage(1, outgoing: true, content: const td.MessageUnsupported());
    expect(resendContent(m), isNull);
  });
}
