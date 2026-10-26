import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/tdlib/td_client.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/core/telegram/widgets/td_file_image.dart';
import 'package:lumina/features/conversation/presentation/widgets/content/rich_cards_content.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/transfer_ring_test.dart' show downloading;
import '../../../helpers/fakes.dart';

void main() {
  Future<FakeTdClient> pump(WidgetTester tester, AppPreferences prefs) async {
    final client = FakeTdClient()
      ..respond = (f) => f is td.GetMapThumbnailFile ? downloading(size: 100) : const td.Ok();
    final m = fakeMessage(
      1,
      content: const td.MessageLocation(
        location: td.Location(latitude: 37.29732, longitude: 49.60227, horizontalAccuracy: 0),
      ),
    );
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: prefs),
          RepositoryProvider<TdClient>.value(value: client),
          RepositoryProvider(create: (_) => FileStore(client)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: LocationContent(
              message: m,
              textColor: Colors.white,
              mutedColor: Colors.grey,
              footer: const SizedBox(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return client;
  }

  testWidgets('a location shows a Telegram map preview', (tester) async {
    final client = await pump(tester, AppPreferences.inMemory());
    final req = client.sentOf<td.GetMapThumbnailFile>().single;
    expect(req.location.latitude, closeTo(37.29732, 1e-6));
    expect(req.chatId, 1);
    expect(find.byType(TdFileImage), findsOneWidget);
  });

  testWidgets('previews can be turned off', (tester) async {
    final client = await pump(tester, AppPreferences.inMemory()..mapPreviews = false);
    expect(client.sentOf<td.GetMapThumbnailFile>(), isEmpty);
    expect(find.byType(TdFileImage), findsNothing);
  });

  test('"Open in" builds the link for the chosen app', () {
    const l = td.Location(latitude: 1.5, longitude: 2.25, horizontalAccuracy: 0);
    expect(mapLink(l, 'Home', MapApp.google), 'https://www.google.com/maps/search/?api=1&query=1.5,2.25');
    expect(
      mapLink(l, 'Home', MapApp.osm),
      'https://www.openstreetmap.org/?mlat=1.5&mlon=2.25#map=16/1.5/2.25',
    );
    expect(mapLink(l, 'Home', MapApp.ask), startsWith('geo:1.5,2.25'));
  });
}
