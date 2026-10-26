import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/core/telegram/widgets/looping_gif.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:video_player/video_player.dart';

import '../../../helpers/fakes.dart';
import '../transfer_ring_test.dart' show downloading;

void main() {
  Future<({FakeTdClient client, List<String> played})> pump(WidgetTester tester, td.File file) async {
    final client = FakeTdClient()..respond = (_) => file;
    final played = <String>[];
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => FileStore(client),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox.square(
              dimension: 100,
              child: LoopingGif(
                file: file,
                player: (f) {
                  played.add(f.path);
                  return VideoPlayerController.networkUrl(Uri.parse('about:blank'));
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (client: client, played: played);
  }

  testWidgets('a GIF not yet downloaded shows its still and fetches the clip', (tester) async {
    final h = await pump(
      tester,
      downloading(size: 100).copyWith(local: downloading().local.copyWith(isDownloadingActive: false)),
    );
    expect(h.client.sentOf<td.DownloadFile>(), hasLength(1));
    expect(h.played, isEmpty);
  });

  testWidgets('a downloaded GIF starts looping', (tester) async {
    final h = await pump(
      tester,
      downloading(size: 100).copyWith(
        local: downloading().local.copyWith(
          path: '/gif.mp4',
          isDownloadingActive: false,
          isDownloadingCompleted: true,
        ),
      ),
    );
    expect(h.played, ['/gif.mp4']);
  });
}
