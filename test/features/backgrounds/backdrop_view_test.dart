import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/core/widgets/glow_background.dart';
import 'package:lumina/features/backgrounds/domain/chat_backdrop.dart';
import 'package:lumina/features/backgrounds/presentation/chat_backdrop_view.dart';

import '../../helpers/fakes.dart';

void main() {
  Future<void> pump(WidgetTester tester, ChatBackdrop b) => tester.pumpWidget(
    RepositoryProvider(
      create: (_) => FileStore(FakeTdClient()),
      child: MaterialApp(
        home: ChatBackdropView(backdrop: b, child: const Text('messages')),
      ),
    ),
  );

  testWidgets('glow keeps Lumina\'s backdrop', (tester) async {
    await pump(tester, const ChatBackdrop(BackdropGlow()));
    expect(find.byType(GlowBackground), findsOneWidget);
    expect(find.text('messages'), findsOneWidget);
  });

  testWidgets('a fill draws its gradient under a dim layer', (tester) async {
    await pump(tester, const ChatBackdrop(BackdropFill([Color(0xFF112233), Color(0xFF445566)]), dim: 0.4));
    expect(find.byKey(const ValueKey('backdrop-fill')), findsOneWidget);
    final dim = tester.widget<ColoredBox>(find.byKey(const ValueKey('backdrop-dim')));
    expect(dim.color.a, closeTo(0.4, 0.01));
  });

  testWidgets('a photo is blurred when asked', (tester) async {
    await pump(tester, const ChatBackdrop(BackdropImage(path: '/me.jpg'), blur: 8));
    expect(find.byType(ImageFiltered), findsOneWidget);
  });
}
