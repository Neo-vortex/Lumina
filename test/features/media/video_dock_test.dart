import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/media/presentation/widgets/video_dock.dart';

void main() {
  Future<List<String>> pump(WidgetTester tester, {bool playing = true, bool muted = false}) async {
    final calls = <String>[];
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: VideoDock(
            position: const Duration(seconds: 42),
            duration: const Duration(minutes: 2, seconds: 15),
            playing: playing,
            speed: 1,
            muted: muted,
            onPlayPause: () => calls.add('play'),
            onSeek: (d) => calls.add('seek ${d.inSeconds}'),
            onSeekBy: (d) => calls.add('by ${d.inSeconds}'),
            onSpeed: (s) => calls.add('speed $s'),
            onMute: () => calls.add('mute'),
            onFullscreen: () => calls.add('full'),
          ),
        ),
      ),
    );
    return calls;
  }

  testWidgets('the dock shows times and every control with a label', (tester) async {
    await pump(tester);
    expect(find.text('0:42'), findsOneWidget);
    expect(find.text('2:15'), findsOneWidget);
    for (final t in [
      'Pause',
      'Back 10 seconds',
      'Forward 10 seconds',
      'Playback speed',
      'Mute',
      'Full screen',
    ]) {
      expect(find.byTooltip(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('controls call back; speed is picked from a sheet', (tester) async {
    final calls = await pump(tester, playing: false, muted: true);
    await tester.tap(find.byTooltip('Play'));
    await tester.tap(find.byTooltip('Back 10 seconds'));
    await tester.tap(find.byTooltip('Forward 10 seconds'));
    await tester.tap(find.byTooltip('Unmute'));
    await tester.tap(find.byTooltip('Playback speed'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('1.5×'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, ['play', 'by -10', 'by 10', 'mute', 'speed 1.5']);
  });
}
