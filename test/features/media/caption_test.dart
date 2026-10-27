import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/media/presentation/screens/media_viewer_screen.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../core/telegram/transfer_ring_test.dart' show downloading;
import '../../helpers/fakes.dart';

void main() {
  testWidgets('a photo caption sits on a dark scrim and a tap hides it', (tester) async {
    final m = fakeMessage(
      1,
      content: td.MessagePhoto(
        photo: td.Photo(
          hasStickers: false,
          sizes: [
            td.PhotoSize(
              type: 'x',
              photo: downloading(size: 100),
              width: 640,
              height: 480,
              progressiveSizes: const [],
            ),
          ],
        ),
        caption: const td.FormattedText(text: 'Sunset at the lake', entities: []),
        showCaptionAboveMedia: false,
        hasSpoiler: false,
        isSecret: false,
      ),
    );
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider(create: (_) => TelegramCache(FakeTdClient())),
          RepositoryProvider(create: (_) => FileStore(FakeTdClient())),
        ],
        child: MaterialApp(home: MediaViewerScreen(messages: [m], initialIndex: 0)),
      ),
    );
    await tester.pump();
    // The chrome and caption come in once the opening flight lands.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Sunset at the lake'), findsOneWidget);
    final scrim = tester.widget<Container>(find.byKey(const ValueKey('caption')));
    final colors = ((scrim.decoration as BoxDecoration).gradient as LinearGradient).colors;
    expect(colors.first.a, greaterThan(0.9), reason: 'dark enough to read on any photo');
    double opacity() => tester
        .widget<AnimatedOpacity>(
          find
              .ancestor(of: find.byKey(const ValueKey('caption')), matching: find.byType(AnimatedOpacity))
              .first,
        )
        .opacity;
    expect(opacity(), 1);
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 500));
    expect(opacity(), 0);
  });
}
