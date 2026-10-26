import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/conversation/presentation/widgets/content/video_note_content.dart';
import 'package:lumina/features/conversation/presentation/widgets/message_bubble.dart';
import 'package:lumina/features/conversation/presentation/widgets/message_rows.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/transfer_ring_test.dart' show downloading;
import '../../../helpers/fakes.dart';

void main() {
  test('dragging on the ring maps the angle clockwise from the top to a fraction', () {
    const size = Size(200, 200);
    expect(ringFraction(const Offset(100, 0), size), closeTo(0, 0.01));
    expect(ringFraction(const Offset(200, 100), size), closeTo(0.25, 0.01));
    expect(ringFraction(const Offset(100, 200), size), closeTo(0.5, 0.01));
    expect(ringFraction(const Offset(0, 100), size), closeTo(0.75, 0.01));
    expect(
      ringFraction(Offset(100 - 100 * math.sin(0.1), 100 - 100 * math.cos(0.1)), size),
      closeTo(1 - 0.1 / (2 * math.pi), 0.01),
    );
  });

  testWidgets('a round video shows only the circle, no rectangular bubble around it', (tester) async {
    final note = td.MessageVideoNote(
      videoNote: td.VideoNote(duration: 7, waveform: '', length: 384, video: downloading(size: 100)),
      isViewed: false,
      isSecret: false,
    );
    final m = fakeMessage(1, content: note);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider(create: (_) => TelegramCache(FakeTdClient())),
          RepositoryProvider(create: (_) => FileStore(FakeTdClient())),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              row: BubbleRow(messages: [m], firstInRun: true, lastInRun: true),
              chat: fakeChat(1),
              isGroup: false,
              isChannel: false,
              animateIn: false,
              highlighted: false,
              selected: false,
              selecting: false,
              onReply: () {},
              onLongPress: () {},
              onTap: () {},
              onReplyQuoteTap: (_) {},
              onReaction: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byType(VideoNoteContent), findsOneWidget);
    final boxes = tester.widgetList<Container>(
      find.ancestor(of: find.byType(VideoNoteContent), matching: find.byType(Container)),
    );
    expect(boxes.where((c) => (c.decoration as BoxDecoration?)?.gradient != null), isEmpty);
  });
}
