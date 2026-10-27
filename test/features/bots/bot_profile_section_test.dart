import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/bots/presentation/bot_profile_section.dart';

import 'bots_repository_test.dart' show bot;

void main() {
  testWidgets('lists about, description, commands and the privacy policy', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: BotProfileSection(info: bot)),
        ),
      ),
    );
    expect(find.text('Weather in a tap'), findsOneWidget);
    expect(find.text('I tell you the weather.'), findsOneWidget);
    expect(find.text('/today'), findsOneWidget);
    expect(find.text('Weather today'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
  });

  testWidgets('empty parts are left out', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BotProfileSection(
            info: bot.copyWith(shortDescription: '', commands: const [], privacyPolicyUrl: ''),
          ),
        ),
      ),
    );
    expect(find.text('Commands'), findsNothing);
    expect(find.text('Privacy policy'), findsNothing);
  });
}
