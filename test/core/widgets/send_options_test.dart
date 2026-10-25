import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib_next/api.dart' as td;
import 'package:lumina/core/telegram/send_options.dart';
import 'package:lumina/core/widgets/send_options_sheet.dart';

void main() {
  test('options map to TDLib scheduling states', () {
    expect(const SendOptions().toTd().schedulingState, isNull);
    expect(const SendOptions(silent: true).toTd().disableNotification, isTrue);
    expect(
      const SendOptions(whenOnline: true).toTd().schedulingState,
      isA<td.MessageSchedulingStateSendWhenOnline>(),
    );
    final at = DateTime.utc(2026, 11, 1, 9);
    final state = SendOptions(scheduleAt: at).toTd().schedulingState as td.MessageSchedulingStateSendAtDate;
    expect(state.sendDate, at.millisecondsSinceEpoch ~/ 1000);
  });

  group('schedule presets', () {
    test('morning: in an hour, this evening, tomorrow, Monday', () {
      // Wednesday 10:15.
      final presets = schedulePresets(DateTime(2026, 10, 28, 10, 15));
      expect(presets.map((p) => p.$1), ['In 1 hour', 'This evening', 'Tomorrow morning', 'Monday morning']);
      expect(presets[0].$2, DateTime(2026, 10, 28, 11, 15));
      expect(presets[3].$2, DateTime(2026, 11, 2, 9));
    });

    test('late evening drops "this evening"; Sunday drops Monday', () {
      final presets = schedulePresets(DateTime(2026, 11, 1, 19, 0));
      expect(presets.map((p) => p.$1), ['In 1 hour', 'Tomorrow morning']);
    });
  });

  testWidgets('the sheet returns the picked option', (tester) async {
    SendOptions? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showSendOptionsSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send without sound'));
    await tester.pumpAndSettle();
    expect(result?.silent, isTrue);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send when online'));
    await tester.pumpAndSettle();
    expect(result?.whenOnline, isTrue);
  });
}
