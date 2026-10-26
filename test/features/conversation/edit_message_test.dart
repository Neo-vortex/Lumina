import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/conversation/data/messages_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

void main() {
  late FakeTdClient client;
  late MessagesRepository repo;

  setUp(() {
    client = FakeTdClient()..respond = (f) => fakeMessage(5);
    repo = MessagesRepository(client: client, prefs: AppPreferences.inMemory());
  });

  test('editing a text message edits its text', () async {
    await repo.edit(fakeMessage(5), 'new');
    expect(client.sentOf<td.EditMessageText>(), hasLength(1));
  });

  test('editing a photo edits its caption and keeps where the caption sits', () async {
    final photo = fakeMessage(
      5,
      content: const td.MessagePhoto(
        photo: td.Photo(hasStickers: false, sizes: []),
        caption: td.FormattedText(text: 'old', entities: []),
        showCaptionAboveMedia: true,
        hasSpoiler: false,
        isSecret: false,
      ),
    );
    await repo.edit(photo, 'new caption');
    expect(client.sentOf<td.EditMessageText>(), isEmpty);
    final c = client.sentOf<td.EditMessageCaption>().single;
    expect(c.caption?.text, 'new caption');
    expect(c.showCaptionAboveMedia, isTrue);
  });
}
