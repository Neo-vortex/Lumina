import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/widgets/glow_sheet.dart';

void main() {
  testWidgets('confirm returns true on the action and false on cancel', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        // GlowButton breathes forever unless motion is reduced.
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(
              await showGlowConfirm(
                context,
                title: 'Delete “Work”?',
                message: 'Chats stay.',
                confirmLabel: 'Delete',
                destructive: true,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete “Work”?'), findsOneWidget);
    expect(find.text('Chats stay.'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(results, [true, false]);
  });

  testWidgets('sheet returns what its content pops', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        // GlowButton breathes forever unless motion is reduced.
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showGlowSheet<String>(
              context,
              title: 'Icon',
              builder: (context) =>
                  TextButton(onPressed: () => Navigator.pop(context, 'Work'), child: const Text('Work')),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Icon'), findsOneWidget);
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(picked, 'Work');
  });
}
