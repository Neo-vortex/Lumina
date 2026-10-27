import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/downloads/bloc/downloads_cubit.dart';
import 'package:lumina/features/downloads/data/download_policy.dart';
import 'package:lumina/features/downloads/data/downloads_repository.dart';
import 'package:lumina/features/downloads/presentation/downloads_screen.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'download_policy_test.dart' show NetForTests;
import 'downloads_cubit_test.dart' show counts, dl;

void main() {
  late FakeTdClient client;
  late DownloadsCubit cubit;

  Future<void> pump(
    WidgetTester tester, {
    List<td.FileDownload> active = const [],
    List<td.FileDownload> done = const [],
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.SearchFileDownloads(onlyActive: true) => td.FoundFileDownloads(
          totalCounts: counts,
          files: active,
          nextOffset: '',
        ),
        td.SearchFileDownloads() => td.FoundFileDownloads(totalCounts: counts, files: done, nextOffset: ''),
        _ => const td.Ok(),
      };
    final repo = DownloadsRepository(client);
    final prefs = AppPreferences.inMemory();
    cubit = DownloadsCubit(repository: repo, files: FileStore(client));
    await cubit.start();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: prefs),
          RepositoryProvider(create: (_) => FileStore(client)),
          RepositoryProvider.value(
            value: TelegramCache.detached()..apply(td.UpdateNewChat(chat: fakeChat(1, title: 'Ada'))),
          ),
          RepositoryProvider(
            create: (_) => DownloadPolicy(repository: repo, prefs: prefs, network: NetForTests()),
          ),
        ],
        child: BlocProvider.value(
          value: cubit,
          child: MaterialApp(
            home: Builder(builder: (c) => DownloadsScreen(openMessage: (_, _, _) {})),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('empty state', (tester) async {
    await pump(tester);
    expect(find.text('No downloads yet'), findsOneWidget);
  });

  testWidgets('pause, and swipe to remove with "also delete"', (tester) async {
    await pump(tester, active: [dl(1)]);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(client.sentOf<td.ToggleDownloadIsPaused>().single.isPaused, isTrue);
    await tester.drag(find.byKey(const ValueKey('download-1')), const Offset(-600, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500)); // the sheet slides in
    await tester.tap(find.text('Also delete the file'));
    await tester.pump();
    await tester.tap(find.text('Remove'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(client.sentOf<td.RemoveFileFromDownloads>().single.deleteFromCache, isTrue);
  });

  testWidgets('filter chips and pause all', (tester) async {
    await pump(tester, active: [dl(1), dl(2)]);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Photos'));
    await tester.pump();
    expect(find.byKey(const ValueKey('download-1')), findsNothing);
    await tester.tap(find.byTooltip('Pause all'));
    await tester.pump();
    expect(client.sentOf<td.ToggleAllDownloadsArePaused>().single.arePaused, isTrue);
  });
}
