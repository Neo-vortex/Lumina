import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/media/presentation/widgets/play_toggle.dart';

void main() {
  const minute = Duration(minutes: 1);

  test('a finished video restarts instead of trying to resume past the end', () {
    expect(
      PlayToggle().tap(playing: false, ended: true, position: minute, duration: minute),
      PlayAction.restart,
    );
    expect(
      PlayToggle().tap(playing: false, ended: false, position: minute, duration: minute),
      PlayAction.restart,
    );
  });

  test('play and pause otherwise', () {
    expect(
      PlayToggle().tap(playing: false, ended: false, position: Duration.zero, duration: minute),
      PlayAction.play,
    );
    expect(
      PlayToggle().tap(playing: true, ended: false, position: Duration.zero, duration: minute),
      PlayAction.pause,
    );
  });

  test('the button shows the tapped state at once and follows the player once it agrees', () {
    final t = PlayToggle();
    t.tap(playing: false, ended: false, position: Duration.zero, duration: minute);
    expect(t.shown(playing: false), isTrue, reason: 'before VLC reports playing');
    expect(t.shown(playing: true), isTrue);
    expect(
      t.shown(playing: false),
      isFalse,
      reason: 'later pauses (end, buffering stop) come from the player',
    );
  });

  test('a second tap before the player reacts toggles from what is shown', () {
    final t = PlayToggle();
    t.tap(playing: false, ended: false, position: Duration.zero, duration: minute);
    expect(t.tap(playing: false, ended: false, position: Duration.zero, duration: minute), PlayAction.pause);
    expect(t.shown(playing: false), isFalse);
  });
}
