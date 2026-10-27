import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/core/telegram/widgets/looping_gif.dart';
import 'package:lumina/features/media_panel/data/media_panel_repository.dart';
import 'package:lumina/features/media_panel/presentation/media_panel.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../core/telegram/transfer_ring_test.dart' show downloading;
import '../../core/telegram/widgets/animated_sticker_test.dart' show tgs;
import '../../helpers/fakes.dart';

const _set = td.StickerSetInfo(
  id: 7,
  title: 'Cats',
  name: 'cats',
  isOwned: false,
  isInstalled: true,
  isArchived: false,
  isOfficial: false,
  stickerType: td.StickerTypeRegular(),
  needsRepainting: false,
  isAllowedAsChatEmojiStatus: false,
  isViewed: true,
  size: 1,
  covers: [],
);

void main() {
  Future<({FakeTdClient client, List<String> emoji})> pump(WidgetTester tester) async {
    final gif = td.Animation(
      duration: 3,
      width: 200,
      height: 200,
      fileName: 'a.mp4',
      mimeType: 'video/mp4',
      hasStickers: false,
      animation: downloading(size: 100).copyWith(id: 30),
    );
    final client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetInstalledStickerSets() => const td.StickerSets(totalCount: 1, sets: [_set]),
        td.GetRecentStickers() => const td.Stickers(stickers: []),
        td.GetStickerSet() => td.StickerSet(
          id: 7,
          title: 'Cats',
          name: 'cats',
          isOwned: false,
          isInstalled: true,
          isArchived: false,
          isOfficial: false,
          stickerType: const td.StickerTypeRegular(),
          needsRepainting: false,
          isAllowedAsChatEmojiStatus: false,
          isViewed: true,
          stickers: [tgs()],
          emojis: const [],
        ),
        td.GetSavedAnimations() => td.Animations(animations: [gif]),
        td.SendMessage() => fakeMessage(9),
        _ => const td.Ok(),
      };
    final prefs = AppPreferences.inMemory();
    final emoji = <String>[];
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: prefs),
          RepositoryProvider(create: (_) => FileStore(client)),
          RepositoryProvider(
            create: (_) => MediaPanelRepository(client: client, prefs: prefs),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MediaPanel(chatId: 5, height: 320, onEmoji: emoji.add, onSent: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return (client: client, emoji: emoji);
  }

  testWidgets('emoji tab: tapping an emoji inserts it and remembers it', (tester) async {
    final h = await pump(tester);
    expect(find.text('Emoji'), findsOneWidget);
    await tester.tap(find.text('😂').first);
    expect(h.emoji, ['😂']);
  });

  testWidgets('stickers tab: packs load and a tap sends the sticker', (tester) async {
    final h = await pump(tester);
    await tester.tap(find.text('Stickers'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.bySemanticsLabel('❤️ sticker'));
    await tester.pump();
    expect(h.client.sentOf<td.SendMessage>().single.inputMessageContent, isA<td.InputMessageSticker>());
  });

  testWidgets('GIFs tab: saved GIFs show and a tap sends one', (tester) async {
    final h = await pump(tester);
    await tester.tap(find.text('GIFs'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.bySemanticsLabel('GIF').first);
    await tester.pump();
    expect(h.client.sentOf<td.SendMessage>().single.inputMessageContent, isA<td.InputMessageAnimation>());
  });

  testWidgets('GIFs never stay paused after a scroll start that has no end', (tester) async {
    await pump(tester);
    await tester.tap(find.text('GIFs'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    bool paused() => tester.widget<LoopingGif>(find.byType(LoopingGif).first).paused;
    expect(paused(), isFalse);
    final grid = tester.element(find.byType(GridView));
    ScrollStartNotification(
      metrics: FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 100,
        pixels: 0,
        viewportDimension: 300,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 3,
      ),
      context: grid,
    ).dispatch(grid);
    await tester.pump();
    expect(paused(), isTrue, reason: 'scrolling pauses the previews');
    await tester.pump(const Duration(milliseconds: 300));
    expect(paused(), isFalse, reason: 'and they play again once things are quiet');
  });
}
