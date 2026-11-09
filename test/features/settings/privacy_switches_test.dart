import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/settings/presentation/screens/settings_category_screen.dart';
import 'package:lumina/features/settings/presentation/settings_category.dart';
import 'package:lumina/features/settings/presentation/widgets/general_settings.dart';

void main() {
  // The page lists const sections, which its own rebuild skips: a switch
  // saved its value but never moved until the section listened itself.
  testWidgets('Ghost mode and the privacy switches move when tapped', (tester) async {
    final prefs = AppPreferences.inMemory();
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: prefs,
        child: MaterialApp(
          home: SettingsCategoryScreen(
            category: SettingsCategory.privacy,
            entries: [SettingsEntry(SettingsCategory.privacy, (_) => const PrivacySettings())],
          ),
        ),
      ),
    );
    bool on(String title) =>
        tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, title)).value;

    expect(on('Ghost mode'), isFalse);
    await tester.tap(find.text('Ghost mode'));
    await tester.pump();
    expect(prefs.ghostMode, isTrue);
    expect(on('Ghost mode'), isTrue);
    expect(on('Appear offline'), isTrue, reason: 'ghost mode turns every switch on');

    await tester.tap(find.text('Appear offline'));
    await tester.pump();
    expect(on('Appear offline'), isFalse);
    expect(on('Ghost mode'), isFalse, reason: 'one switch off is no longer ghost mode');
  });
}
