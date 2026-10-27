import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/core/telegram/widgets/looping_gif.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:video_player/video_player.dart';

import '../../../helpers/fakes.dart';
import '../transfer_ring_test.dart' show downloading;

td.File gif(int id) => downloading(size: 100).copyWith(
  id: id,
  local: downloading().local.copyWith(
    path: '/gif$id.mp4',
    isDownloadingActive: false,
    isDownloadingCompleted: true,
  ),
);

void main() {
  testWidgets('a budget caps live players; a waiting GIF starts when one leaves', (tester) async {
    final players = <String>[];
    Widget grid(List<int> ids) => RepositoryProvider(
      create: (_) => FileStore(FakeTdClient()),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GifBudget(
          max: 2,
          child: Row(
            children: [
              for (final i in ids)
                SizedBox.square(
                  key: ValueKey(i),
                  dimension: 50,
                  child: LoopingGif(
                    file: gif(i),
                    player: (f) {
                      players.add(f.path);
                      return VideoPlayerController.networkUrl(Uri.parse('about:blank'));
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(grid([1, 2, 3]));
    await tester.pump();
    expect(players, ['/gif1.mp4', '/gif2.mp4'], reason: 'the third waits on its still');

    await tester.pumpWidget(grid([2, 3]));
    await tester.pump();
    expect(players, ['/gif1.mp4', '/gif2.mp4', '/gif3.mp4'], reason: 'a freed slot goes to the waiting GIF');
  });
}
