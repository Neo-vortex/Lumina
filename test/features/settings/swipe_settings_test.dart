import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/gestures/swipe_actions.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/settings/presentation/screens/swipe_settings_screen.dart';

void main() {
  Future<AppPreferences> pump(WidgetTester tester) async {
    final prefs = AppPreferences.inMemory();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: prefs,
        child: const MaterialApp(home: SwipeSettingsScreen()),
      ),
    );
    return prefs;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('picking an action for a direction stores it', (tester) async {
    final prefs = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('message-right')));
    await settle(tester);
    await tester.tap(find.text('Delete').last);
    await settle(tester);
    expect(prefs.messageSwipe(SwipeSide.right), MessageSwipe.delete);

    await tester.tap(find.byKey(const ValueKey('chat-left')));
    await settle(tester);
    await tester.tap(find.text('Mute / unmute').last);
    await settle(tester);
    expect(prefs.chatSwipe(SwipeSide.left), ChatSwipe.mute);
  });

  testWidgets('the react emoji can be changed', (tester) async {
    final prefs = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('swipe-emoji')));
    await settle(tester);
    await tester.tap(find.text('🔥').last);
    await settle(tester);
    expect(prefs.swipeEmoji, '🔥');
  });
}
