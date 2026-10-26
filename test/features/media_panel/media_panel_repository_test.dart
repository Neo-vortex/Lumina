import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/media_panel/data/media_panel_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import '../../core/telegram/widgets/animated_sticker_test.dart' show tgs;

void main() {
  test('recent emoji: most recent first, no duplicates', () {
    final repo = MediaPanelRepository(client: FakeTdClient(), prefs: AppPreferences.inMemory());
    repo
      ..useEmoji('😀')
      ..useEmoji('🔥')
      ..useEmoji('😀');
    expect(repo.recentEmoji, ['😀', '🔥']);
  });

  test('a sticker is sent by file id with its size and emoji', () async {
    final client = FakeTdClient()..respond = (_) => fakeMessage(9);
    await MediaPanelRepository(client: client, prefs: AppPreferences.inMemory()).sendSticker(5, tgs());
    final sent = client.sentOf<td.SendMessage>().single;
    expect(sent.chatId, 5);
    final content = sent.inputMessageContent as td.InputMessageSticker;
    expect((content.sticker.sticker as td.InputFileId).id, 1);
    expect(content.emoji, '❤️');
  });
}
