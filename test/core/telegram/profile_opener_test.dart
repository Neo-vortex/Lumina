import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:provider/provider.dart';

import 'package:lumina/core/telegram/profile_opener.dart';
import 'package:lumina/core/telegram/widgets/formatted_text_view.dart';

void main() {
  group('usernameOf', () {
    String? of(String url) => ProfileOpener.usernameOf(Uri.parse(url));

    test('plain profile links', () {
      expect(of('https://t.me/durov'), 'durov');
      expect(of('https://telegram.me/durov/'), 'durov');
      expect(of('https://durov.t.me'), 'durov');
      expect(of('tg://resolve?domain=durov'), 'durov');
    });

    test('other t.me links are not profiles', () {
      expect(of('https://t.me/durov/123'), isNull);
      expect(of('https://t.me/somebot?start=abc'), isNull);
      expect(of('https://t.me/addlist'), isNull);
      expect(of('https://t.me/proxy?server=x'), isNull);
      expect(of('https://t.me/+AbCdEf'), isNull);
      expect(of('https://t.me/joinchat'), isNull);
      expect(of('tg://resolve?domain=durov&post=4'), isNull);
      expect(of('https://example.com/durov'), isNull);
    });
  });

  testWidgets('mentions and name mentions open through the opener', (tester) async {
    final opened = <Object>[];
    final opener = ProfileOpener(
      openUser: (_, id) async => opened.add(id),
      openUsername: (_, name) async => opened.add(name),
    );
    const text = td.FormattedText(
      text: 'hi @alice and Bob',
      entities: [
        td.TextEntity(offset: 3, length: 6, type: td.TextEntityTypeMention()),
        td.TextEntity(offset: 14, length: 3, type: td.TextEntityTypeMentionName(userId: 42)),
      ],
    );
    await tester.pumpWidget(
      Provider<ProfileOpener>.value(
        value: opener,
        child: const MaterialApp(home: Scaffold(body: FormattedTextView(text))),
      ),
    );
    final rich = tester.widget<RichText>(find.byType(RichText).first);
    void tapSpan(String piece) {
      var done = false;
      rich.text.visitChildren((span) {
        if (!done && span is TextSpan && span.text == piece) {
          (span.recognizer! as TapGestureRecognizer).onTap!();
          done = true;
        }
        return !done;
      });
      expect(done, isTrue, reason: piece);
    }

    tapSpan('@alice');
    tapSpan('Bob');
    expect(opened, ['alice', 42]);
  });
}
