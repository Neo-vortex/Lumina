import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/auth/domain/account_capabilities.dart';
import 'package:lumina/features/settings/presentation/screens/settings_screen.dart';
import 'package:lumina/features/settings/presentation/settings_category.dart';

import '../../helpers/fakes.dart';

/// The Log out button breathes forever, so pumpAndSettle never settles.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late AppPreferences prefs;

  setUp(() => prefs = AppPreferences.inMemory());

  Future<void> pumpHub(WidgetTester tester, {bool bot = false}) async {
    final me = fakeUser(bot: bot);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: prefs),
          RepositoryProvider(
            create: (_) => SettingsEntries(
              (_) => [
                SettingsEntry(SettingsCategory.connection, (_) => const Text('proxy entry')),
                SettingsEntry(SettingsCategory.data, (_) => const Text('storage entry')),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SettingsHub(me: me, caps: AccountCapabilities.forUser(me)),
          ),
        ),
      ),
    );
    await _settle(tester);
  }

  Future<void> open(WidgetTester tester, String category) async {
    await tester.scrollUntilVisible(find.text(category), 100);
    await tester.tap(find.text(category));
    await _settle(tester);
  }

  testWidgets('the top page lists categories, not individual settings', (tester) async {
    await pumpHub(tester);
    for (final title in ['Privacy', 'Chats', 'Media & voice', 'Data & storage']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    // No feature filed anything under Notifications here, so it has no page.
    expect(find.text('Notifications'), findsNothing);
    await tester.scrollUntilVisible(find.text('About & licenses'), 100);
    expect(find.text('Connection & calls'), findsOneWidget);
    expect(find.text('Ghost mode'), findsNothing);
    expect(find.text('Autoplay videos and GIFs'), findsNothing);
  });

  testWidgets('a category opens its own page with its settings', (tester) async {
    await pumpHub(tester);
    await open(tester, 'Privacy');
    expect(find.widgetWithText(AppBar, 'Privacy'), findsOneWidget);
    expect(find.text('Ghost mode'), findsOneWidget);
    expect(find.text('Hide typing indicator'), findsOneWidget);
    expect(find.text('Autoplay videos and GIFs'), findsNothing);
  });

  testWidgets('feature entries appear only under their category', (tester) async {
    await pumpHub(tester);
    await open(tester, 'Connection & calls');
    expect(find.text('proxy entry'), findsOneWidget);
    expect(find.text('storage entry'), findsNothing);
    await tester.pageBack();
    await _settle(tester);
    await open(tester, 'Data & storage');
    expect(find.text('storage entry'), findsOneWidget);
    expect(find.text('proxy entry'), findsNothing);
  });

  testWidgets('the Privacy row summarises ghost mode', (tester) async {
    prefs.ghostMode = true;
    await pumpHub(tester);
    expect(find.text('Ghost mode on'), findsOneWidget);
  });

  testWidgets('bots get no Privacy page and only bot-relevant chat settings', (tester) async {
    await pumpHub(tester, bot: true);
    expect(find.text('Privacy'), findsNothing);
    await open(tester, 'Chats');
    expect(find.text('Show link previews in chats'), findsOneWidget);
    expect(find.text('Hide stories'), findsNothing);
    expect(find.text('Hide channel ads'), findsNothing);
  });
}
