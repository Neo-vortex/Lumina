import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/features/downloads/bloc/downloads_cubit.dart';
import 'package:lumina/features/downloads/data/downloads_repository.dart';
import 'package:lumina/features/downloads/presentation/downloads_ring.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'downloads_cubit_test.dart' show counts, dl;

void main() {
  Future<DownloadsCubit> pump(WidgetTester tester, List<td.FileDownload> active, {void Function()? onOpen}) async {
    final client = FakeTdClient()
      ..respond = (f) => f is td.SearchFileDownloads
          ? td.FoundFileDownloads(totalCounts: counts, files: f.onlyActive ? active : const [], nextOffset: '')
          : const td.Ok();
    final cubit = DownloadsCubit(repository: DownloadsRepository(client), files: FileStore(client));
    await cubit.start();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(home: Scaffold(body: DownloadsRing(onOpen: onOpen ?? () {}))),
      ),
    );
    await tester.pump();
    return cubit;
  }

  testWidgets('hidden with nothing to download', (tester) async {
    await pump(tester, const []);
    expect(find.bySemanticsLabel(RegExp('^Downloads')), findsNothing);
  });

  testWidgets('shows while downloading and opens the screen', (tester) async {
    var opened = false;
    await pump(tester, [dl(1)], onOpen: () => opened = true);
    expect(find.bySemanticsLabel(RegExp('^Downloads, 1 active')), findsOneWidget);
    await tester.tap(find.byType(DownloadsRing));
    expect(opened, isTrue);
  });
}
