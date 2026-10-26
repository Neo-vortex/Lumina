import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/file_store.dart';
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
  Future<StateSetter> pump(WidgetTester tester, td.File file, {bool fullResolution = false}) async {
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
                return TdFileImage(file: file, autoDownload: false, fullResolution: fullResolution);
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
}
