import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/backgrounds/domain/chat_backdrop.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../core/telegram/transfer_ring_test.dart' show downloading;
import '../../helpers/fakes.dart';

td.ChatBackground bg(td.BackgroundType type, {td.Document? doc, int dimming = 0}) => td.ChatBackground(
  background: td.Background(id: 1, isDefault: false, isDark: true, name: 'b', document: doc, type: type),
  darkThemeDimming: dimming,
);

void main() {
  final wallpaperDoc = td.Document(
    fileName: 'w.jpg',
    mimeType: 'image/jpeg',
    document: downloading(size: 100),
  );

  test('a chat\'s Telegram wallpaper wins, blurred if Telegram says so, dimmed by its dimming', () {
    final chat = fakeChat(1).copyWith(
      background: bg(
        const td.BackgroundTypeWallpaper(isBlurred: true, isMoving: false),
        doc: wallpaperDoc,
        dimming: 40,
      ),
    );
    final b = resolveBackdrop(chat, AppPreferences.inMemory());
    expect(b.spec, isA<BackdropImage>());
    expect(b.blur, greaterThan(0));
    expect(b.dim, closeTo(0.4, 0.001));
  });

  test('a Telegram fill becomes its colours', () {
    final chat = fakeChat(1).copyWith(
      background: bg(
        const td.BackgroundTypeFill(
          fill: td.BackgroundFillGradient(topColor: 0x112233, bottomColor: 0x445566, rotationAngle: 0),
        ),
      ),
    );
    final spec = resolveBackdrop(chat, AppPreferences.inMemory()).spec as BackdropFill;
    expect(spec.colors, [const Color(0xFF112233), const Color(0xFF445566)]);
  });

  test('no chat background: the Settings default, Lumina glow out of the box', () {
    final prefs = AppPreferences.inMemory();
    expect(resolveBackdrop(fakeChat(1), prefs).spec, isA<BackdropGlow>());
    prefs
      ..backdropKind = 'photo'
      ..backdropPath = '/me.jpg'
      ..backdropBlur = 8
      ..backdropDim = 0.3;
    final b = resolveBackdrop(fakeChat(1), prefs);
    expect((b.spec as BackdropImage).path, '/me.jpg');
    expect(b.blur, 8);
    expect(b.dim, 0.3);
  });
}
