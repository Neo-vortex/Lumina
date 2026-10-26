import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/conversation/presentation/widgets/content/expired_media_content.dart';
import 'package:lumina_tdlib/api.dart' as td;

void main() {
  Future<void> pump(WidgetTester tester, td.MessageContent c, {required bool outgoing}) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ExpiredMediaContent(
          content: c,
          outgoing: outgoing,
          color: Colors.white,
          footer: const Text('01:51'),
        ),
      ),
    ),
  );

  testWidgets('an expired photo explains itself instead of "Photo expired"', (tester) async {
    await pump(tester, const td.MessageExpiredPhoto(), outgoing: false);
    expect(find.text('Disappearing photo'), findsOneWidget);
    expect(find.text('You opened it — it\'s gone now'), findsOneWidget);
    expect(find.text('Photo expired'), findsNothing);
  });

  testWidgets('your own reads from your side; videos and voice say what they were', (tester) async {
    await pump(tester, const td.MessageExpiredVideo(), outgoing: true);
    expect(find.text('Disappearing video'), findsOneWidget);
    expect(find.text('Opened, and gone for good'), findsOneWidget);
    await pump(tester, const td.MessageExpiredVoiceNote(), outgoing: true);
    expect(find.text('Disappearing voice message'), findsOneWidget);
  });
}
