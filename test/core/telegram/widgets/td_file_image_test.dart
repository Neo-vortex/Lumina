import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/core/telegram/widgets/file_progress.dart';
import 'package:lumina/core/telegram/widgets/td_file_image.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../helpers/fakes.dart';
import '../transfer_ring_test.dart' show downloading;

td.File downloaded() => downloading(size: 100).copyWith(
  local: downloading().local.copyWith(
    path: '/x.jpg',
    isDownloadingActive: false,
    isDownloadingCompleted: true,
  ),
);

void main() {
  Future<StateSetter> pump(
    WidgetTester tester,
    td.File file, {
    bool fullResolution = false,
    Uint8List? placeholder,
  }) async {
    late StateSetter rebuild;
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => FileStore(FakeTdClient()),
        child: Center(
          child: SizedBox(
            width: 100,
            height: 100,
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return TdFileImage(
                  file: file,
                  autoDownload: false,
                  fullResolution: fullResolution,
                  placeholderBytes: placeholder,
                );
              },
            ),
          ),
        ),
      ),
    );
    return rebuild;
  }

  testWidgets('the file stream is created once, not on every build', (tester) async {
    final rebuild = await pump(tester, downloading(size: 100));
    final first = tester.widget<StreamBuilder<td.File>>(find.byType(StreamBuilder<td.File>)).stream;
    rebuild(() {});
    await tester.pump();
    expect(
      identical(tester.widget<StreamBuilder<td.File>>(find.byType(StreamBuilder<td.File>)).stream, first),
      isTrue,
    );
  });

  testWidgets('a photo decodes at its laid-out size, not full resolution', (tester) async {
    await pump(tester, downloaded());
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>());
    expect((image.image as ResizeImage).width, 300, reason: '100 dp at the test DPR of 3');
  });

  testWidgets('the viewer can ask for full resolution', (tester) async {
    await pump(tester, downloaded(), fullResolution: true);
    expect(tester.widget<Image>(find.byType(Image)).image, isNot(isA<ResizeImage>()));
  });

  testWidgets('the placeholder is smoothed by upscaling, not a per-frame blur layer', (tester) async {
    await pump(tester, downloading(size: 100), placeholder: base64Decode(_png1x1));
    expect(find.byType(ImageFiltered), findsNothing);
    expect(tester.widget<Image>(find.byType(Image)).filterQuality, FilterQuality.medium);
  });

  testWidgets('an image mounting a FileBuilder of the same file does not rebuild it mid-build', (
    tester,
  ) async {
    late StateSetter set;
    var show = false;
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => FileStore(FakeTdClient()),
        // The image is inside the builder, as AnimatedSticker's fallback is,
        // and mounts after the builder is already listening.
        child: StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return FileBuilder(
              file: downloading(size: 100),
              builder: (_, _) => SizedBox(
                width: 50,
                height: 50,
                child: show ? TdFileImage(file: downloading(size: 100), autoDownload: false) : null,
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    set(() => show = true);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

const _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
