import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/tdlib/td_client.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/features/backgrounds/presentation/background_picker_screen.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../core/telegram/transfer_ring_test.dart' show downloading;
import '../../helpers/fakes.dart';

void main() {
  final gallery = td.Background(
    id: 77,
    isDefault: false,
    isDark: true,
    name: 'night',
    document: td.Document(
      fileName: 'n.jpg',
      mimeType: 'image/jpeg',
      document: downloading(size: 100).copyWith(id: 5),
    ),
    type: const td.BackgroundTypeWallpaper(isBlurred: false, isMoving: false),
  );

  Future<(FakeTdClient, AppPreferences)> pump(WidgetTester tester, {td.Chat? chat}) async {
    final client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetInstalledBackgrounds() => td.Backgrounds(backgrounds: [gallery]),
        _ => const td.Ok(),
      };
    final prefs = AppPreferences.inMemory();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: prefs),
          RepositoryProvider<TdClient>.value(value: client),
          RepositoryProvider(create: (_) => FileStore(client)),
        ],
        child: MaterialApp(home: BackgroundPickerScreen(chat: chat)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return (client, prefs);
  }

  testWidgets('default mode: a fill with dim is saved to Settings', (tester) async {
    final (_, prefs) = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('fill-1')));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pump();
    expect(prefs.backdropKind, 'fill');
    expect(prefs.backdropColors, isNotEmpty);
  });

  testWidgets('chat mode: a gallery wallpaper is set on the chat in Telegram', (tester) async {
    final (client, _) = await pump(tester, chat: fakeChat(9));
    await tester.tap(find.byKey(const ValueKey('gallery-77')));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pump();
    final sent = client.sentOf<td.SetChatBackground>().single;
    expect(sent.chatId, 9);
    expect((sent.background as td.InputBackgroundRemote).backgroundId, 77);
    expect(sent.onlyForSelf, isTrue);
  });
}
