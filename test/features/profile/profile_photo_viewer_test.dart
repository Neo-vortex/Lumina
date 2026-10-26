import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/features/media/presentation/screens/media_viewer_screen.dart';
import 'package:lumina/features/profile/presentation/profile_photo_viewer.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../core/telegram/transfer_ring_test.dart' show downloading;
import '../../helpers/fakes.dart';

td.ChatPhoto photo(int id, {bool downloaded = true}) => td.ChatPhoto(
  id: id,
  addedDate: 0,
  sizes: [
    td.PhotoSize(
      type: 'x',
      photo: downloaded
          ? downloading(size: 100).copyWith(
              id: id,
              local: downloading().local.copyWith(
                path: '/p$id.jpg',
                isDownloadingActive: false,
                isDownloadingCompleted: true,
              ),
            )
          : downloading(size: 100).copyWith(id: id),
      width: 640,
      height: 640,
      progressiveSizes: const [],
    ),
  ],
);

void main() {
  testWidgets('full-screen profile photo: zoomable, pages, and saves the current one', (tester) async {
    final saved = <String>[];
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => FileStore(FakeTdClient()),
        child: MaterialApp(
          home: ProfilePhotoViewer(
            photos: [photo(1), photo(2)],
            initial: 1,
            save: (path) async {
              saved.add(path);
              return true;
            },
          ),
        ),
      ),
    );
    expect(find.byType(DoubleTapZoom), findsWidgets);
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Save to gallery'));
    await tester.pump();
    expect(saved, ['/p2.jpg']);
    await tester.pump(const Duration(seconds: 4));
  });
}
