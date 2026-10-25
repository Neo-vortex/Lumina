import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../../core/media/audio_playback.dart';
import '../../../../../core/media/waveform.dart';
import '../../../../../core/telegram/display.dart';
import '../../../../../core/telegram/widgets/formatted_text_view.dart';
import '../../../../../core/telegram/widgets/td_file_image.dart';
import '../../../../../core/theme/glow_colors.dart';
import '../../../../voice/presentation/widgets/waveform_bars.dart';
import '../../../bloc/conversation_cubit.dart';
import '../conversation_extensions.dart';

/// Voice message: play/pause, seekable waveform, time, speed chip, and an
/// accessory slot (transcription) supplied through [ConversationExtensions].
class VoiceNoteContent extends StatelessWidget {
  const VoiceNoteContent({
    super.key,
    required this.message,
    required this.voice,
    required this.isListened,
    required this.textColor,
    required this.mutedColor,
    required this.outgoing,
    required this.footer,
  });

  final td.Message message;
  final td.VoiceNote voice;
  final bool isListened;
  final Color textColor;
  final Color mutedColor;
  final bool outgoing;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final player = context.read<AudioPlayback>();
    final key = '${message.chatId}:${message.id}';
    final values = Waveform.decode(voice.waveform);
    final accessory = ConversationExtensions.of(context).voiceAccessory(context, message);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 6),
      child: ValueListenableBuilder<PlaybackState>(
        valueListenable: player.state,
        builder: (context, s, _) {
          final current = s.isFor(key);
          final total = current && s.duration > Duration.zero
              ? s.duration
              : Duration(seconds: voice.duration);
          final progress = current && total > Duration.zero
              ? s.position.inMilliseconds / total.inMilliseconds
              : 0.0;
          final accent = outgoing ? GlowColors.onAccent : GlowColors.cyan;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _PlayButton(
                    playing: current && s.playing,
                    color: accent,
                    onTap: () => player
                        .toggle(
                          key,
                          voice.voice,
                          mime: voice.mimeType.isEmpty ? 'audio/ogg' : voice.mimeType,
                          onCompleted: () {},
                        )
                        .then((_) {
                          if (!isListened && !message.isOutgoing && context.mounted) {
                            context.read<ConversationCubit>().openViewOnce(message).ignore();
                          }
                        }),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: WaveformBars(
                        values: values.isEmpty ? List.filled(40, 6) : values,
                        color: (outgoing ? GlowColors.onAccent : GlowColors.textMuted).withValues(
                          alpha: 0.45,
                        ),
                        activeColor: accent,
                        progress: progress,
                        onSeek: current ? (f) => player.seek(key, total * f) : null,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 52, top: 2),
                child: Row(
                  children: [
                    Text(
                      current ? Display.duration(s.position.inSeconds) : Display.duration(voice.duration),
                      style: TextStyle(color: mutedColor, fontSize: 12),
                    ),
                    if (!isListened && !message.isOutgoing)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: GlowColors.cyan),
                      ),
                    if (current) ...[
                      const SizedBox(width: 8),
                      _SpeedChip(speed: s.speed, color: accent, onTap: player.cycleSpeed),
                    ],
                    const Spacer(),
                    footer,
                  ],
                ),
              ),
              ?accessory,
            ],
          );
        },
      ),
    );
  }
}

/// Music / audio file with title, performer, cover and the shared player.
class MusicContent extends StatelessWidget {
  const MusicContent({
    super.key,
    required this.message,
    required this.audio,
    required this.caption,
    required this.textColor,
    required this.mutedColor,
    required this.outgoing,
    required this.footer,
  });

  final td.Message message;
  final td.Audio audio;
  final td.FormattedText caption;
  final Color textColor;
  final Color mutedColor;
  final bool outgoing;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final player = context.read<AudioPlayback>();
    final key = '${message.chatId}:${message.id}';
    final accent = outgoing ? GlowColors.onAccent : GlowColors.cyan;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 6),
      child: ValueListenableBuilder<PlaybackState>(
        valueListenable: player.state,
        builder: (context, s, _) {
          final current = s.isFor(key);
          final total = current && s.duration > Duration.zero
              ? s.duration
              : Duration(seconds: audio.duration);
          final pos = current ? s.position : Duration.zero;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      if (audio.albumCoverThumbnail != null)
                        ClipOval(
                          child: SizedBox.square(
                            dimension: 44,
                            child: TdFileImage(file: audio.albumCoverThumbnail!.file),
                          ),
                        ),
                      _PlayButton(
                        playing: current && s.playing,
                        color: accent,
                        onTap: () => player.toggle(
                          key,
                          audio.audio,
                          mime: audio.mimeType.isEmpty ? 'audio/mpeg' : audio.mimeType,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          audio.title.isEmpty ? audio.fileName : audio.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          audio.performer.isEmpty ? Display.duration(audio.duration) : audio.performer,
                          maxLines: 1,
                          style: TextStyle(color: mutedColor, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (current)
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: pos.inMilliseconds.clamp(0, total.inMilliseconds).toDouble(),
                        max: total.inMilliseconds <= 0 ? 1 : total.inMilliseconds.toDouble(),
                        activeColor: accent,
                        onChanged: (v) => player.seek(key, Duration(milliseconds: v.round())),
                      ),
                    ),
                    _SpeedChip(speed: s.speed, color: accent, onTap: player.cycleSpeed),
                  ],
                ),
              if (caption.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: FormattedTextView(caption, style: TextStyle(color: textColor)),
                ),
              Align(alignment: Alignment.centerRight, child: footer),
            ],
          );
        },
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.color, required this.onTap});

  final bool playing;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: playing ? 'Pause' : 'Play',
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.18),
          border: Border.all(color: color.withValues(alpha: 0.8)),
          boxShadow: playing ? glow(color, intensity: 0.5) : null,
        ),
        child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: color),
      ),
    ),
  );
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({required this.speed, required this.color, required this.onTap});

  final double speed;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Playback speed ${speed.toStringAsFixed(2)} times',
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minWidth: 40, minHeight: 28),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(
          '${speed == speed.roundToDouble() ? speed.toStringAsFixed(0) : speed.toString()}×',
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    ),
  );
}
