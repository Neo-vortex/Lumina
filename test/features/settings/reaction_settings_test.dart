import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/settings/presentation/widgets/general_settings.dart';

void main() {
  Future<AppPreferences> pump(WidgetTester tester) async {
    final prefs = AppPreferences.inMemory();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: prefs,
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: ReactionSettings())),
        ),
      ),
    );
    return prefs;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('quick reactions are picked in order, up to five', (tester) async {
    final prefs = await pump(tester);
    await tester.tap(find.text('Quick reactions'));
    await settle(tester);
    // Start over, then pick in order.
    await tester.tap(find.text('Clear'));
    await tester.pump();
    for (final e in ['🎉', '🙏', '👏', '😢']) {
      await tester.tap(find.text(e).last);
      await tester.pump();
    }
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(prefs.quickReactions, ['🎉', '🙏', '👏', '😢']);
  });

  testWidgets('animated emoji can be switched off', (tester) async {
    final prefs = await pump(tester);
    await tester.tap(find.text('Animated emoji'));
    await tester.pump();
    expect(prefs.animatedEmoji, isFalse);
  });
}
