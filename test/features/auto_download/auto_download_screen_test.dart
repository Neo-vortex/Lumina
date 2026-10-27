import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/auto_download/data/auto_download_service.dart';
import 'package:lumina/features/auto_download/domain/auto_download_policy.dart';
import 'package:lumina/features/auto_download/presentation/auto_download_screen.dart';

import '../../helpers/fakes.dart';
import 'fake_monitor.dart';

void main() {
  late AutoDownloadService service;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    service = AutoDownloadService(
      client: FakeTdClient(),
      prefs: AppPreferences.inMemory(),
      cache: TelegramCache.detached(),
      network: FakeMonitor(),
    );
    addTearDown(service.dispose);
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: service,
        child: const MaterialApp(home: AutoDownloadScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('opens on the current network and shows its preset', (tester) async {
    await pump(tester);
    expect(find.text('Wi-Fi'), findsOneWidget);
    expect(find.text('Now on Wi-Fi'), findsOneWidget);
    final high = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'High'));
    expect(high.selected, isTrue);
  });

  testWidgets('picking a preset applies it to the selected network only', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Mobile'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Off'));
    await tester.pump();
    expect(service.policy(NetworkKind.mobile).preset, AutoDownloadPreset.off);
    expect(service.policy(NetworkKind.wifi).preset, AutoDownloadPreset.high);
  });

  testWidgets('toggling a cell makes the preset custom', (tester) async {
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('Music in Channels'));
    await tester.pump();
    expect(service.policy(NetworkKind.wifi).isOn(MediaKind.music, ChatKind.channels), isFalse);
    expect(service.policy(NetworkKind.wifi).preset, AutoDownloadPreset.custom);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Custom')).selected, isTrue);
  });

  testWidgets('the video limit slider snaps to the size stops', (tester) async {
    await pump(tester);
    final slider = find.byKey(const ValueKey('video-limit'));
    await tester.scrollUntilVisible(slider, 200, scrollable: find.byType(Scrollable).first);
    await tester.drag(slider, const Offset(-2000, 0));
    await tester.pump();
    expect(service.policy(NetworkKind.wifi).maxVideoSize, AutoDownloadPolicy.sizeStops.first);
    expect(find.text('Up to 100 KB'), findsOneWidget);
  });
}
