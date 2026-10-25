import 'package:flutter/material.dart';

import '../../../../core/media/waveform.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../voice/data/voice_recorder.dart';
import '../../../voice/presentation/widgets/waveform_bars.dart';

/// Shown while dictating: live level meter and "Listening…", or progress
/// while Whisper turns the speech into text.
class DictationBar extends StatelessWidget {
  const DictationBar({super.key, required this.recorder, required this.transcribing, required this.progress});

  final VoiceRecorder recorder;
  final bool transcribing;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final levels = recorder.levels.length > 60
        ? recorder.levels.sublist(recorder.levels.length - 60)
        : recorder.levels;
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 4, right: 14),
      decoration: BoxDecoration(
        color: GlowColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: GlowColors.cyan.withValues(alpha: 0.8)),
        boxShadow: glow(GlowColors.cyan, intensity: 0.3),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Cancel dictation',
            icon: const Icon(Icons.close_rounded, color: GlowColors.textMuted),
            onPressed: transcribing ? null : recorder.cancel,
          ),
          Semantics(
            liveRegion: true,
            child: Text(
              transcribing ? 'Writing… ${(progress * 100).round()}%' : 'Listening…',
              style: const TextStyle(color: GlowColors.cyan),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: transcribing
                ? LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    minHeight: 3,
                    color: GlowColors.cyan,
                  )
                : WaveformBars(
                    values: Waveform.normalise(levels),
                    color: GlowColors.cyan.withValues(alpha: 0.8),
                    activeColor: GlowColors.cyan,
                    height: 26,
                  ),
          ),
        ],
      ),
    );
  }
}
