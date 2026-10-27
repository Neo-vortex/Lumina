import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/tdlib/td_client.dart';
import 'package:lumina/core/telegram/auto_download_gate.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/features/conversation/presentation/widgets/content/auto_fetch.dart';
import 'package:lumina/features/conversation/presentation/widgets/content/media_content.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/transfer_ring_test.dart' show downloading;
import '../../../helpers/fakes.dart';

class _Gate implements AutoDownloadGate {
  _Gate(this.allowed, {this.preloadLargeVideos = false});

  final Set<MediaKind> allowed;
  final asked = <(int, MediaKind, int)>[];

  @override
  final bool preloadLargeVideos;

  @override
  bool allows({required int chatId, required MediaKind media, required int size}) {
    asked.add((chatId, media, size));
    return allowed.contains(media);
  }
}

td.File idle(int id, int size) {
  final f = downloading(size: size);
  return f.copyWith(id: id, local: f.local.copyWith(isDownloadingActive: false, downloadedSize: 0));
}

td.MessageContent voice(td.File f) => td.MessageVoiceNote(
  voiceNote: td.VoiceNote(duration: 3, waveform: '', mimeType: 'audio/ogg', voice: f),
  caption: const td.FormattedText(text: '', entities: []),
  isListened: false,
);

td.MessageContent document(td.File f) => td.MessageDocument(
  document: td.Document(fileName: 'a.pdf', mimeType: 'application/pdf', document: f),
  caption: const td.FormattedText(text: '', entities: []),
);

td.MessageContent video(td.File f) => td.MessageVideo(
  video: td.Video(
    duration: 9,
    width: 1,
    height: 1,
    fileName: 'v.mp4',
    mimeType: 'video/mp4',
    hasStickers: false,
    supportsStreaming: true,
    video: f,
  ),
  alternativeVideos: const [],
  storyboards: const [],
  startTimestamp: 0,
  caption: const td.FormattedText(text: '', entities: []),
  showCaptionAboveMedia: false,
  hasSpoiler: false,
  isSecret: false,
);

void main() {
  late FakeTdClient client;

  Future<void> pump(WidgetTester tester, AutoDownloadGate gate, td.MessageContent content) async {
    client = FakeTdClient()..respond = (f) => idle(1, 1);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<TdClient>.value(value: client),
          RepositoryProvider(create: (_) => FileStore(client)),
          RepositoryProvider<AutoDownloadGate>.value(value: gate),
        ],
        child: AutoFetch(
          messages: [fakeMessage(5, chatId: 3, content: content)],
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('an allowed voice message downloads on its own', (tester) async {
    final gate = _Gate({MediaKind.voice});
    await pump(tester, gate, voice(idle(11, 2000)));
    expect(gate.asked.single, (3, MediaKind.voice, 2000));
    expect(client.sentOf<td.DownloadFile>().single.fileId, 11);
  });

  testWidgets('a file the settings do not allow waits for a tap', (tester) async {
    await pump(tester, _Gate({}), document(idle(12, 5000)));
    expect(client.sentOf<td.DownloadFile>(), isEmpty);
  });

  testWidgets('a large video only preloads its start when that is on', (tester) async {
    await pump(tester, _Gate({}, preloadLargeVideos: true), video(idle(13, 50000000)));
    final req = client.sentOf<td.DownloadFile>().single;
    expect(req.fileId, 13);
    expect(req.offset, 0);
    expect(req.limit, AutoFetch.preloadBytes);
  });

  testWidgets('finished downloads are left alone', (tester) async {
    final done = idle(14, 10);
    await pump(
      tester,
      _Gate(MediaKind.values.toSet()),
      voice(done.copyWith(local: done.local.copyWith(isDownloadingCompleted: true, path: '/x'))),
    );
    expect(client.sentOf<td.DownloadFile>(), isEmpty);
  });

  for (final allowed in [true, false]) {
    testWidgets('a photo in a bubble downloads only when allowed ($allowed)', (tester) async {
      final client = FakeTdClient()..respond = (f) => idle(21, 300);
      final photo = td.MessagePhoto(
        photo: td.Photo(
          hasStickers: false,
          sizes: [
            td.PhotoSize(
              type: 'x',
              photo: idle(21, 300),
              width: 800,
              height: 600,
              progressiveSizes: const [],
            ),
          ],
        ),
        caption: const td.FormattedText(text: '', entities: []),
        showCaptionAboveMedia: false,
        hasSpoiler: false,
        isSecret: false,
      );
      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<TdClient>.value(value: client),
            RepositoryProvider(create: (_) => FileStore(client)),
            RepositoryProvider<AutoDownloadGate>.value(value: _Gate(allowed ? {MediaKind.photos} : {})),
          ],
          child: MaterialApp(
            home: SizedBox(
              width: 300,
              height: 200,
              child: MediaTile(
                message: fakeMessage(5, content: photo),
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(client.sentOf<td.DownloadFile>().map((d) => d.fileId), allowed ? [21] : isEmpty);
    });
  }
}
