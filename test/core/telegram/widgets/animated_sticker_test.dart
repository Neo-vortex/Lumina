import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/core/telegram/widgets/animated_sticker.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../helpers/fakes.dart';
import '../transfer_ring_test.dart' show downloading;

td.Sticker tgs() => td.Sticker(
  id: 1,
  setId: 2,
  width: 512,
  height: 512,
  emoji: '❤️',
  format: const td.StickerFormatTgs(),
  fullType: const td.StickerFullTypeRegular(),
  sticker: downloading(size: 100).copyWith(
    local: downloading().local.copyWith(
      path: '/a.tgs',
      isDownloadingActive: false,
      isDownloadingCompleted: true,
    ),
  ),
);

void main() {
  Future<void> pump(WidgetTester tester, AppPreferences prefs) => tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: prefs),
        RepositoryProvider(create: (_) => FileStore(FakeTdClient())),
      ],
      child: MaterialApp(
        home: Center(child: AnimatedSticker(sticker: tgs(), size: 40)),
      ),
    ),
  );

  testWidgets('a downloaded TGS plays through Lottie', (tester) async {
    await pump(tester, AppPreferences.inMemory());
    expect(find.byType(LottieBuilder), findsOneWidget);
  });

  testWidgets('with animations off it shows the static emoji instead', (tester) async {
    await pump(tester, AppPreferences.inMemory()..animatedEmoji = false);
    expect(find.byType(LottieBuilder), findsNothing);
    expect(find.text('❤️'), findsOneWidget);
  });
}
