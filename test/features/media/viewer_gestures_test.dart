import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/core/telegram/widgets/td_file_image.dart';
import 'package:lumina/features/media/presentation/screens/media_viewer_screen.dart';
import 'package:lumina/features/media/presentation/widgets/media_flight.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../core/telegram/transfer_ring_test.dart' show downloading;
import '../../helpers/fakes.dart';

td.Message photo(int id, {String caption = '', int album = 0}) => fakeMessage(
  id,
  albumId: album,
  content: td.MessagePhoto(
    photo: td.Photo(
      hasStickers: false,
      sizes: [
        td.PhotoSize(
          type: 'x',
          photo: downloading(size: 100),
          width: 800,
          height: 600,
          progressiveSizes: const [],
        ),
      ],
    ),
    caption: td.FormattedText(text: caption, entities: const []),
    showCaptionAboveMedia: false,
    hasSpoiler: false,
    isSecret: false,
  ),
);

void main() {
  late List<td.Message> messages;
  final tileKey = GlobalKey();

  Future<void> openViewer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider(create: (_) => TelegramCache(FakeTdClient())),
          RepositoryProvider(create: (_) => FileStore(FakeTdClient())),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: GestureDetector(
                  onTap: () => MediaViewerScreen.open(context, messages),
                  child: SizedBox(
                    key: tileKey,
                    width: 200,
                    height: 150,
                    child: const ColoredBox(color: Colors.red),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    MediaFlight.register(messages.first.id, tileKey);
    await tester.tap(find.byKey(tileKey));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Rect pictureRect(WidgetTester tester) => tester.getRect(find.byType(TdFileImage).last);

  bool viewerOpen() => find.byType(MediaViewerScreen).evaluate().isNotEmpty;

  testWidgets('opens out of the tile: the first frame sits where the tile is', (tester) async {
    messages = [photo(1)];
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider(create: (_) => TelegramCache(FakeTdClient())),
          RepositoryProvider(create: (_) => FileStore(FakeTdClient())),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: GestureDetector(
                  onTap: () => MediaViewerScreen.open(context, messages),
                  child: SizedBox(
                    key: tileKey,
                    width: 200,
                    height: 150,
                    child: const ColoredBox(color: Colors.red),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    MediaFlight.register(1, tileKey);
    final tile = tester.getRect(find.byKey(tileKey));
    await tester.tap(find.byKey(tileKey));
    await tester.pump();
    await tester.pump();
    final clip = tester.getRect(find.byType(ClipRRect).last);
    expect(clip.center.dx, closeTo(tile.center.dx, 2));
    expect(clip.center.dy, closeTo(tile.center.dy, 2));
    expect(MediaFlight.hidden.value, 1, reason: 'the tile steps aside while the picture flies');
    await tester.pump(const Duration(milliseconds: 400));
    expect(MediaFlight.hidden.value, isNull);
  });

  testWidgets('a long drag down follows the finger, then flies home and closes', (tester) async {
    messages = [photo(1)];
    await openViewer(tester);
    final rest = pictureRect(tester);
    final g = await tester.startGesture(rest.center);
    await g.moveBy(const Offset(0, 20));
    await tester.pump();
    final taken = pictureRect(tester);
    await g.moveBy(const Offset(0, 100));
    await tester.pump();
    final dragged = pictureRect(tester);
    expect(taken.center.dy - rest.center.dy, lessThan(4), reason: 'no jump when the drag takes over');
    expect(dragged.center.dy, closeTo(taken.center.dy + 100, 3), reason: '1:1 with the finger');
    expect(dragged.width, lessThan(rest.width), reason: 'shrinks as it goes');
    await g.moveBy(const Offset(0, 250));
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(viewerOpen(), isFalse);
    expect(MediaFlight.hidden.value, isNull);
  });

  testWidgets('a short slow drag springs back', (tester) async {
    messages = [photo(1)];
    await openViewer(tester);
    final rest = pictureRect(tester);
    final g = await tester.startGesture(rest.center);
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(0, 8));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pumpAndSettle();
    expect(viewerOpen(), isTrue);
    expect(pictureRect(tester).center.dy, closeTo(rest.center.dy, 0.5));
  });

  testWidgets('pinch zooms about the fingers and settles inside the limits', (tester) async {
    messages = [photo(1)];
    await openViewer(tester);
    final rest = pictureRect(tester);
    final c = rest.center;
    final a = await tester.startGesture(c - const Offset(40, 0));
    final b = await tester.startGesture(c + const Offset(40, 0));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(-8, 0));
      await b.moveBy(const Offset(8, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final zoomed = pictureRect(tester);
    expect(zoomed.width, greaterThan(rest.width * 1.5));
    // The test moves one finger then the other, so the midpoint wobbles by
    // 4 px between events and the zoom magnifies that; still anchored.
    expect(zoomed.center.dx, closeTo(c.dx, 16), reason: 'the point between the fingers stays put');
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(viewerOpen(), isTrue, reason: 'a pinch never dismisses');
    expect(pictureRect(tester).width, greaterThan(rest.width * 1.5));
  });

  testWidgets('album: swiping pages, and every picture shows the album caption', (tester) async {
    messages = [photo(1, caption: 'Trip', album: 9), photo(2, album: 9)];
    await openViewer(tester);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('Trip'), findsOneWidget);
    await tester.flingFrom(const Offset(300, 400), const Offset(-200, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('Trip'), findsOneWidget);
  });

  testWidgets('back flies the picture home, then pops', (tester) async {
    messages = [photo(1)];
    await openViewer(tester);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pump();
    expect(viewerOpen(), isTrue, reason: 'still flying');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(viewerOpen(), isFalse);
  });
}
