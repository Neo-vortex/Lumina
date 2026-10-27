import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/core/telegram/widgets/file_progress.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

td.File downloading({int size = 0}) => td.File(
  id: 1,
  size: size,
  expectedSize: size,
  local: const td.LocalFile(
    path: '',
    canBeDownloaded: true,
    canBeDeleted: false,
    isDownloadingActive: true,
    isDownloadingCompleted: false,
    downloadOffset: 0,
    downloadedPrefixSize: 0,
    downloadedSize: 10,
  ),
  remote: const td.RemoteFile(
    id: '',
    uniqueId: '',
    isUploadingActive: false,
    isUploadingCompleted: true,
    uploadedSize: 0,
  ),
);

void main() {
  testWidgets('a download of unknown size shows no endless spinner', (tester) async {
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => FileStore(FakeTdClient()),
        child: MaterialApp(home: TransferRing(file: downloading())),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a known size shows the progress ring', (tester) async {
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => FileStore(FakeTdClient()),
        child: MaterialApp(home: TransferRing(file: downloading(size: 100))),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('FileBuilder creates its stream once, not on every build', (tester) async {
    late StateSetter rebuild;
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => FileStore(FakeTdClient()),
        child: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return FileBuilder(file: downloading(), builder: (_, _) => const SizedBox());
          },
        ),
      ),
    );
    StreamBuilder<td.File> sb() => tester.widget(find.byType(StreamBuilder<td.File>));
    final first = sb().stream;
    rebuild(() {});
    await tester.pump();
    expect(identical(sb().stream, first), isTrue);
  });

  testWidgets('a tap that starts a download reports it', (tester) async {
    final client = FakeTdClient()..respond = (_) => downloading(size: 100);
    final base = downloading(size: 100);
    final idle = base.copyWith(local: base.local.copyWith(isDownloadingActive: false));
    td.File? started;
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => FileStore(client),
        child: MaterialApp(
          home: TransferRing(file: idle, onStart: (f) => started = f),
        ),
      ),
    );
    await tester.tap(find.byType(TransferRing));
    await tester.pump();
    expect(started?.id, idle.id);
  });
}
