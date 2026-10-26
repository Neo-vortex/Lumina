import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/theme/glow_colors.dart';
import 'package:lumina/core/theme/glow_theme.dart';
import 'package:lumina/features/transcription/presentation/widgets/transcript_view.dart';

void main() {
  testWidgets('the translate chip draws its label in the bubble colour, not the theme grey', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildGlowTheme(),
        home: Scaffold(
          body: TranscriptChip(
            icon: Icons.translate_rounded,
            label: 'Translate to English',
            color: GlowColors.onAccent,
            onPressed: () {},
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('Translate to English'));
    final style = DefaultTextStyle.of(tester.element(find.text('Translate to English'))).style
        .merge(text.style);
    expect(style.color, GlowColors.onAccent);
  });
}
