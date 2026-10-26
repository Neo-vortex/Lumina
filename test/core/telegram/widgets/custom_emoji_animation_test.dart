import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/custom_emoji_store.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/core/telegram/widgets/formatted_text_view.dart';
import 'package:lumina/core/telegram/widgets/td_file_image.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../helpers/fakes.dart';
import '../transfer_ring_test.dart' show downloading;
import 'animated_sticker_test.dart' show tgs;

void main() {
  Future<void> pump(WidgetTester tester, AppPreferences prefs) async {
    final sticker = tgs().copyWith(
      fullType: const td.StickerFullTypeCustomEmoji(customEmojiId: 77, needsRepainting: false),
      thumbnail: td.Thumbnail(
        format: const td.ThumbnailFormatWebp(),
        width: 100,
        height: 100,
        file: downloading().copyWith(id: 9),
      ),
    );
    final client = FakeTdClient()..respond = (_) => td.Stickers(stickers: [sticker]);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: prefs),
          RepositoryProvider(create: (_) => FileStore(FakeTdClient())),
          RepositoryProvider(create: (_) => CustomEmojiStore(client)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: FormattedTextView(
              td.FormattedText(
                text: 'hi 😀',
                entities: [
                  td.TextEntity(offset: 3, length: 2, type: td.TextEntityTypeCustomEmoji(customEmojiId: 77)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  testWidgets('a TGS custom emoji animates in text', (tester) async {
    await pump(tester, AppPreferences.inMemory());
    expect(find.byType(LottieBuilder), findsOneWidget);
    expect(
      tester.widget<LottieBuilder>(find.byType(LottieBuilder)).repeat,
      isTrue,
      reason: 'loops like Telegram',
    );
  });

  testWidgets('with animations off it shows its static image', (tester) async {
    await pump(tester, AppPreferences.inMemory()..animatedEmoji = false);
    expect(find.byType(LottieBuilder), findsNothing);
    expect(find.byType(TdFileImage), findsOneWidget);
  });
}
