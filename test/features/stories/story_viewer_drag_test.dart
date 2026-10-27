import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/media/ffmpeg_service.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/stories/data/stories_repository.dart';
import 'package:lumina/features/stories/presentation/screens/story_viewer_screen.dart';

import '../../helpers/fakes.dart';

void main() {
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final client = FakeTdClient();
    final prefs = AppPreferences.inMemory();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider(create: (_) => TelegramCache.detached()),
          RepositoryProvider.value(value: prefs),
          RepositoryProvider(
            create: (_) => StoriesRepository(client: client, prefs: prefs, ffmpeg: FfmpegService()),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(StoryViewerScreen.route([1, 2])),
                  child: const Text('main'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();
  }

  Offset storyTop(WidgetTester tester) => tester.getTopLeft(find.byType(PageView));
  bool open_(WidgetTester tester) => find.byType(StoryViewerScreen).evaluate().isNotEmpty;

  testWidgets('drag down follows the finger, shrinks, and a long drag closes', (tester) async {
    await open(tester);
    final g = await tester.startGesture(const Offset(180, 300));
    await g.moveBy(const Offset(0, 30));
    await tester.pump();
    final before = storyTop(tester);
    await g.moveBy(const Offset(0, 100));
    await tester.pump();
    final after = storyTop(tester);
    expect(after.dy - before.dy, greaterThan(80), reason: 'tracks the finger');
    expect(tester.getSize(find.byType(PageView)), const Size(360, 800), reason: 'layout size unchanged');
    await g.moveBy(const Offset(0, 200));
    await g.up();
    await tester.pumpAndSettle();
    expect(open_(tester), isFalse);
    expect(find.text('main'), findsOneWidget);
  });

  testWidgets('a short slow drag springs back', (tester) async {
    await open(tester);
    final rest = storyTop(tester);
    final g = await tester.startGesture(const Offset(180, 300));
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pumpAndSettle();
    expect(open_(tester), isTrue);
    expect((storyTop(tester) - rest).distance, lessThan(0.5));
  });

  testWidgets("the next person's page is built before the swipe reaches it", (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey(2), skipOffstage: false), findsOneWidget);
  });
}
