import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/core/telegram/widgets/td_file_image.dart';
import 'package:lumina/features/conversation/presentation/widgets/pinned_banner.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/transfer_ring_test.dart' show downloading;
import '../../../helpers/fakes.dart';

void main() {
  Future<void> pump(WidgetTester tester, td.Message m) => tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => TelegramCache(FakeTdClient())),
        RepositoryProvider(create: (_) => FileStore(FakeTdClient())),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PinnedBanner(message: m, onTap: () {}),
        ),
      ),
    ),
  );

  testWidgets('a pinned video shows a small thumbnail with a play mark', (tester) async {
    final video = td.MessageVideo(
      video: td.Video(
        duration: 12,
        width: 640,
        height: 360,
        fileName: 'v.mp4',
        mimeType: 'video/mp4',
        hasStickers: false,
        supportsStreaming: true,
        thumbnail: td.Thumbnail(
          format: const td.ThumbnailFormatJpeg(),
          width: 90,
          height: 50,
          file: downloading(),
        ),
        video: downloading(size: 100),
      ),
      alternativeVideos: const [],
      storyboards: const [],
      startTimestamp: 0,
      caption: const td.FormattedText(text: '', entities: []),
      showCaptionAboveMedia: false,
      hasSpoiler: false,
      isSecret: false,
    );
    await pump(tester, fakeMessage(1, content: video));
    expect(find.byType(TdFileImage), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('a text pin has no thumbnail', (tester) async {
    await pump(tester, fakeMessage(1, text: 'meeting at 5'));
    expect(find.byType(TdFileImage), findsNothing);
  });
}
