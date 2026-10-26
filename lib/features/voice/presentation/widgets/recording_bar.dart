import 'package:flutter/material.dart';

import '../../../../core/telegram/display.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../data/voice_recorder.dart';
import 'live_waveform.dart';
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
    final values = recorder.result?.waveform ?? const <int>[];
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
          if (recording) _LevelHalo(level: recorder.levels.isEmpty ? 0 : recorder.levels.last),
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
            child: recording
                ? LiveWaveform(levels: () => recorder.levels, color: GlowColors.coral)
                : WaveformBars(
                    values: values,
                    color: GlowColors.textMuted,
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

/// The recording light: a coral dot whose glow breathes with your voice.
class _LevelHalo extends StatelessWidget {
  const _LevelHalo({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final l = level.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox.square(
        dimension: 22,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            width: 10 + 10 * l,
            height: 10 + 10 * l,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: GlowColors.coral.withValues(alpha: 0.25 + 0.2 * l),
            ),
            alignment: Alignment.center,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: GlowColors.coral,
                boxShadow: glow(GlowColors.coral, intensity: 0.4 + 0.6 * l),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
