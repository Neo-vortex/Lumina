import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/media/waveform.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../data/voice_recorder.dart';
import 'waveform_bars.dart';

/// Replaces the text field while recording (live waveform, timer, cancel)
/// and in review (preview waveform, discard). The send orb is the stop /
/// send control (spec §9.3: the orb morphs to stop).
class RecordingBar extends StatelessWidget {
  const RecordingBar({super.key, required this.recorder, this.onTranscribe});

  final VoiceRecorder recorder;

  /// Offered in review when Whisper is available.
  final VoidCallback? onTranscribe;

  @override
  Widget build(BuildContext context) {
    final recording = recorder.phase == RecorderPhase.recording;
    final values = recording
        ? Waveform.normalise(
            recorder.levels.length > 60
                ? recorder.levels.sublist(recorder.levels.length - 60)
                : recorder.levels,
          )
        : (recorder.result?.waveform ?? const []);
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 4, right: 12),
      decoration: BoxDecoration(
        color: GlowColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: (recording ? GlowColors.coral : GlowColors.outlineStrong).withValues(alpha: 0.8),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: recording ? 'Cancel recording' : 'Discard recording',
            icon: const Icon(Icons.delete_outline_rounded, color: GlowColors.coral),
            onPressed: recorder.cancel,
          ),
          if (recording) const _RecDot(),
          Semantics(
            liveRegion: true,
            label: recording ? 'Recording ${Display.duration(recorder.elapsed.inSeconds)}' : null,
            child: Text(
              Display.duration(
                (recording ? recorder.elapsed : recorder.result?.duration ?? Duration.zero).inSeconds,
              ),
              style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: WaveformBars(
              values: values,
              color: recording ? GlowColors.coral.withValues(alpha: 0.85) : GlowColors.textMuted,
              activeColor: GlowColors.amber,
              height: 28,
            ),
          ),
          if (!recording && onTranscribe != null)
            IconButton(
              tooltip: 'Convert to text',
              icon: const Icon(Icons.text_fields_rounded, color: GlowColors.cyan),
              onPressed: onTranscribe,
            ),
        ],
      ),
    );
  }
}

class _RecDot extends StatefulWidget {
  const _RecDot();

  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot> {
  var _on = true;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 600), (_) => setState(() => _on = !_on));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: AnimatedOpacity(
      opacity: _on ? 1 : 0.25,
      duration: const Duration(milliseconds: 300),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: GlowColors.coral,
          boxShadow: glow(GlowColors.coral),
        ),
      ),
    ),
  );
}
