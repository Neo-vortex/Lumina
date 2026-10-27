enum PlayAction { play, pause, restart }

/// The play button's logic, apart from libVLC so it can be tested.
///
/// libVLC reports a play or pause a beat after it is asked, so the button
/// shows the tapped state until the player agrees. A finished video can't
/// resume (VLC sits in "ended"), so a tap there restarts it.
class PlayToggle {
  bool? _intent;

  PlayAction tap({
    required bool playing,
    required bool ended,
    required Duration position,
    required Duration duration,
  }) {
    final atEnd = ended || (duration > Duration.zero && position >= duration);
    final showing = shown(playing: playing);
    if (showing) {
      _intent = false;
      return PlayAction.pause;
    }
    _intent = true;
    return atEnd ? PlayAction.restart : PlayAction.play;
  }

  /// Whether the button shows "playing", given what the player reports.
  bool shown({required bool playing}) {
    if (_intent == playing) _intent = null;
    return _intent ?? playing;
  }
}
