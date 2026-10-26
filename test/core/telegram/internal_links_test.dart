import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/internal_links.dart';

Future<BuildContext> contextOf(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    Builder(
      builder: (c) {
        ctx = c;
        return const SizedBox();
      },
    ),
  );
  return ctx;
}

void main() {
  test('parse adds https to bare t.me links and keeps tg:// links', () {
    expect(InternalLinks.parse('t.me/addlist/AbC')!.toString(), 'https://t.me/addlist/AbC');
    expect(InternalLinks.parse('tg://addlist?slug=AbC')!.scheme, 'tg');
    expect(InternalLinks.parse('  '), isNull);
    final links = InternalLinks([
      InternalLinkHandler(matches: (u) => u.scheme == 'tg', open: (_, _) async {}),
    ]);
    expect(links.canOpen('tg://addlist?slug=a'), isTrue);
    expect(links.canOpen('https://example.com'), isFalse);
  });

  testWidgets('the first matching handler opens the link', (tester) async {
    final opened = <String>[];
    final links = InternalLinks([
      InternalLinkHandler(
        matches: (u) => u.path.startsWith('/addlist'),
        open: (_, u) async => opened.add('a $u'),
      ),
      InternalLinkHandler(matches: (u) => true, open: (_, u) async => opened.add('b $u')),
    ]);
    final ctx = await contextOf(tester);
    expect(await links.tryOpen(ctx, 'https://t.me/addlist/x'), isTrue);
    expect(opened, ['a https://t.me/addlist/x']);
  });

  testWidgets('no handler: not handled', (tester) async {
    final ctx = await contextOf(tester);
    expect(await InternalLinks().tryOpen(ctx, 'https://example.com'), isFalse);
  });
}
