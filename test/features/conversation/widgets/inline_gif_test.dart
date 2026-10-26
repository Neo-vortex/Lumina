import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/core/telegram/widgets/looping_gif.dart';
import 'package:lumina/features/conversation/presentation/widgets/content/media_content.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/transfer_ring_test.dart' show downloading;
import '../../../helpers/fakes.dart';

void main() {
  testWidgets('a GIF in chat loops inline; tapping it does not open the big player', (tester) async {
    var opened = 0;
    final m = fakeMessage(
      1,
      content: td.MessageAnimation(
        animation: td.Animation(
          duration: 3,
          width: 200,
          height: 200,
          fileName: 'a.mp4',
          mimeType: 'video/mp4',
          hasStickers: false,
          animation: downloading(size: 100).copyWith(id: 30),
        ),
        caption: const td.FormattedText(text: '', entities: []),
        showCaptionAboveMedia: false,
        hasSpoiler: false,
        isSecret: false,
      ),
    );
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => FileStore(FakeTdClient()),
        child: MaterialApp(
          home: Center(
            child: SizedBox.square(
              dimension: 200,
              child: MediaTile(message: m, onTap: () => opened++),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(LoopingGif), findsOneWidget);
    await tester.tap(find.byType(MediaTile));
    expect(opened, 0);
  });
}
