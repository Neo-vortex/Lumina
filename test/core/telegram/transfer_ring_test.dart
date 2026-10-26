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
}
