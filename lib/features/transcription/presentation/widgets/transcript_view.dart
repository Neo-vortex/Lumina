import 'package:flutter/material.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';
import '../../data/transcription_center.dart';

/// "Transcribe" button and the collapsible transcript under a voice
/// message, with "Translate to English" (spec §8.2).
class TranscriptView extends StatelessWidget {
  const TranscriptView({super.key, required this.center, required this.message, required this.color});

  final TranscriptionCenter center;
  final td.Message message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: center,
      builder: (context, _) {
        final e = center.entry(message);
        if (e == null) {
          return Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: color,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: () => center.transcribe(message),
              icon: const Icon(Icons.text_fields_rounded, size: 18),
              label: const Text('Transcribe'),
            ),
          );
        }
        final text = e.showTranslation ? e.translatedText : e.text;
        return AnimatedSize(
          duration: Motion.standard,
          curve: Motion.enter,
          alignment: Alignment.topLeft,
          child: Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: color.withValues(alpha: 0.7), width: 2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      e.showTranslation ? Icons.translate_rounded : Icons.notes_rounded,
                      size: 15,
                      color: color,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(switch (e.status) {
                        TranscriptStatus.working =>
                          e.progress > 0 ? 'Transcribing… ${(e.progress * 100).round()}%' : 'Transcribing…',
                        TranscriptStatus.failed => 'Transcription failed',
                        TranscriptStatus.done =>
                          e.showTranslation
                              ? 'English translation'
                              : 'Transcript${e.language != null ? ' · ${e.language!.toUpperCase()}' : ''}',
                      }, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    if (e.status == TranscriptStatus.done)
                      IconButton(
                        tooltip: e.collapsed ? 'Expand transcript' : 'Collapse transcript',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          e.collapsed ? Icons.expand_more_rounded : Icons.expand_less_rounded,
                          color: color,
                          size: 20,
                        ),
                        onPressed: () => center.toggleCollapsed(message),
                      ),
                  ],
                ),
                if (e.status == TranscriptStatus.working)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: LinearProgressIndicator(
                      value: e.progress > 0 ? e.progress : null,
                      minHeight: 2,
                      color: color,
                    ),
                  ),
                if (e.status == TranscriptStatus.failed)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.error ?? '',
                              style: const TextStyle(color: GlowColors.error, fontSize: 13),
                            ),
                          ),
                          TextButton(onPressed: () => center.transcribe(message), child: const Text('Retry')),
                        ],
                      ),
                    ),
                  ),
                if (e.status != TranscriptStatus.failed && text != null && !e.collapsed) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 8),
                    child: SelectableText(text, style: TextStyle(color: color, fontSize: 14, height: 1.4)),
                  ),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (!e.showTranslation)
                        ActionChip(
                          avatar: Icon(Icons.translate_rounded, size: 16, color: color),
                          label: const Text('Translate to English'),
                          onPressed: () => center.transcribe(message, translate: true),
                        )
                      else
                        ActionChip(
                          avatar: Icon(Icons.undo_rounded, size: 16, color: color),
                          label: const Text('Original'),
                          onPressed: () => center.showOriginal(message),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
