import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/folders/presentation/widgets/folder_settings.dart';

void main() {
  test('gesture is the default folder picker', () {
    expect(AppPreferences.inMemory().folderPicker, FolderPickerStyle.gesture);
  });

  testWidgets('the setting switches to classic', (tester) async {
    final prefs = AppPreferences.inMemory();
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: prefs,
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: FolderSettings())),
        ),
      ),
    );
    expect(find.text('Hold the title to swipe through folders'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('folder-picker-style')));
    await tester.pump();
    expect(prefs.folderPicker, FolderPickerStyle.classic);
    expect(find.text('Tap the title for a list'), findsOneWidget);
  });
}
