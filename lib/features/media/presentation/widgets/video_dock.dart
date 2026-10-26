import 'package:flutter/material.dart';

import '../../../../core/telegram/display.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_sheet.dart';

/// The video player's controls: a dark scrim rising from the bottom and a
/// glass dock with a thick seek bar, ±10 s, play/pause, speed, mute and
/// full screen. Pure UI; the player feeds it state and handles callbacks.
class VideoDock extends StatefulWidget {
  const VideoDock({
    super.key,
    required this.position,
    required this.duration,
    required this.playing,
    required this.speed,
    required this.muted,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSeekBy,
    required this.onSpeed,
    required this.onMute,
    this.onFullscreen,
    this.buffered,
    this.downloaded,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final double speed;
  final bool muted;

  /// End of the buffered range, for streamed media.
  final Duration? buffered;

  /// 0..1 of the file downloaded, while it isn't complete.
  final double? downloaded;

  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration> onSeekBy;
  final ValueChanged<double> onSpeed;
  final VoidCallback onMute;
  final VoidCallback? onFullscreen;

  static const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  State<VideoDock> createState() => _VideoDockState();
}

class _VideoDockState extends State<VideoDock> {
  double? _dragMs;

  static const _label = TextStyle(
    color: Colors.white,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  Future<void> _pickSpeed() async {
    final s = await showGlowSheet<double>(
      context,
      title: 'Playback speed',
      accent: GlowColors.cyan,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            for (final s in VideoDock.speeds)
              ChoiceChip(
                label: Text('$s×'),
                selected: s == widget.speed,
                selectedColor: GlowColors.cyan.withValues(alpha: 0.3),
                onSelected: (_) => Navigator.pop(context, s),
              ),
          ],
        ),
      ),
    );
    if (s != null) widget.onSpeed(s);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.duration.inMilliseconds.toDouble();
    final pos = (_dragMs ?? widget.position.inMilliseconds.toDouble()).clamp(0.0, total <= 0 ? 0.0 : total);
    final buffered = widget.buffered?.inMilliseconds.toDouble().clamp(pos, total <= 0 ? pos : total);
    final dragging = _dragMs != null;
    return DecoratedBox(
      // Strong enough that white controls read over any frame.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment(0, -0.2),
          colors: [Color(0xE6000000), Color(0x99000000), Color(0x00000000)],
          stops: [0, 0.45, 1],
        ),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
            decoration: BoxDecoration(
              color: const Color(0xB3101318),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(Display.duration(Duration(milliseconds: pos.round()).inSeconds), style: _label),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: dragging ? 6 : 4,
                          activeTrackColor: GlowColors.cyan,
                          inactiveTrackColor: Colors.white24,
                          secondaryActiveTrackColor: Colors.white54,
                          thumbColor: Colors.white,
                          overlayColor: GlowColors.cyan.withValues(alpha: 0.2),
                          thumbShape: RoundSliderThumbShape(enabledThumbRadius: dragging ? 10 : 7),
                          showValueIndicator: ShowValueIndicator.onDrag,
                          valueIndicatorColor: const Color(0xE6101318),
                          valueIndicatorTextStyle: _label,
                        ),
                        child: Slider(
                          value: pos,
                          max: total <= 0 ? 1 : total,
                          secondaryTrackValue: buffered,
                          label: Display.duration(Duration(milliseconds: pos.round()).inSeconds),
                          onChangeStart: total <= 0 ? null : (x) => setState(() => _dragMs = x),
                          onChanged: total <= 0 ? null : (x) => setState(() => _dragMs = x),
                          onChangeEnd: total <= 0
                              ? null
                              : (x) {
                                  setState(() => _dragMs = null);
                                  widget.onSeek(Duration(milliseconds: x.round()));
                                },
                        ),
                      ),
                    ),
                    Text(Display.duration(widget.duration.inSeconds), style: _label),
                  ],
                ),
                Row(
                  children: [
                    _DockButton(
                      icon: Icons.replay_10_rounded,
                      tooltip: 'Back 10 seconds',
                      onTap: () => widget.onSeekBy(const Duration(seconds: -10)),
                    ),
                    const SizedBox(width: 2),
                    _PlayButton(playing: widget.playing, onTap: widget.onPlayPause),
                    const SizedBox(width: 2),
                    _DockButton(
                      icon: Icons.forward_10_rounded,
                      tooltip: 'Forward 10 seconds',
                      onTap: () => widget.onSeekBy(const Duration(seconds: 10)),
                    ),
                    const Spacer(),
                    if (widget.downloaded case final d?)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          '↓ ${(d * 100).floor()}%',
                          semanticsLabel: 'Downloaded ${(d * 100).floor()} percent',
                          style: _label.copyWith(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    Tooltip(
                      message: 'Playback speed',
                      child: InkWell(
                        onTap: _pickSpeed,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white38),
                          ),
                          child: Text('${widget.speed}×', style: _label),
                        ),
                      ),
                    ),
                    _DockButton(
                      icon: widget.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      tooltip: widget.muted ? 'Unmute' : 'Mute',
                      onTap: widget.onMute,
                    ),
                    if (widget.onFullscreen != null)
                      _DockButton(
                        icon: Icons.fullscreen_rounded,
                        tooltip: 'Full screen',
                        onTap: widget.onFullscreen!,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    visualDensity: VisualDensity.compact,
    icon: Icon(icon, color: Colors.white, size: 26),
  );
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: playing ? 'Pause' : 'Play',
    child: Material(
      color: Colors.white,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(
          dimension: 48,
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.black,
            size: 30,
          ),
        ),
      ),
    ),
  );
}
