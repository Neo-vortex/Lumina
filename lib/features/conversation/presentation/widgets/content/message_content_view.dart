import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../../../core/telegram/display.dart';
import '../../../../../core/telegram/telegram_cache.dart';
import 'audio_content.dart';
import 'document_content.dart';
import 'generic_content.dart';
import 'media_content.dart';
import 'sticker_content.dart';
import 'video_note_content.dart';
import 'text_content.dart';

/// Content types rendered edge-to-edge (no text padding around them).
bool isMediaContent(td.MessageContent c) => switch (c) {
  td.MessagePhoto() || td.MessageVideo() || td.MessageAnimation() || td.MessageSticker() => true,
  td.MessageVideoNote() => true,
  _ => false,
};

/// Picks the renderer for a message's content. [messages] has more than one
/// entry for albums. [footer] (time, read state) is placed by the renderer.
class MessageContentView extends StatelessWidget {
  const MessageContentView({
    super.key,
    required this.messages,
    required this.textColor,
    required this.mutedColor,
    required this.outgoing,
    required this.footer,
    required this.overlayFooter,
  });

  final List<td.Message> messages;
  final Color textColor;
  final Color mutedColor;
  final bool outgoing;
  final Widget footer;

  /// Footer variant for drawing over media (light text).
  final Widget overlayFooter;

  @override
  Widget build(BuildContext context) {
    final m = messages.last;
    if (messages.length > 1 && messages.every((x) => visualOf(x.content) != null)) {
      return MediaCluster(messages: messages, textColor: textColor, footer: overlayFooter);
    }
    return switch (m.content) {
      td.MessageText(:final text) => TextContent(text: text, color: textColor, footer: footer),
      td.MessagePhoto() || td.MessageVideo() || td.MessageAnimation() => VisualContent(
        message: m,
        textColor: textColor,
        footer: captionOf(m.content) == null ? overlayFooter : footer,
      ),
      td.MessageDocument(:final document, :final caption) => DocumentContent(
        document: document,
        caption: caption,
        textColor: textColor,
        mutedColor: mutedColor,
        footer: footer,
      ),
      td.MessageSticker(:final sticker) => StickerContent(sticker: sticker, footer: overlayFooter),
      td.MessageVoiceNote(:final voiceNote, :final isListened) => VoiceNoteContent(
        message: m,
        voice: voiceNote,
        isListened: isListened,
        textColor: textColor,
        mutedColor: mutedColor,
        outgoing: outgoing,
        footer: footer,
      ),
      td.MessageAudio(:final audio, :final caption) => MusicContent(
        message: m,
        audio: audio,
        caption: caption,
        textColor: textColor,
        mutedColor: mutedColor,
        outgoing: outgoing,
        footer: footer,
      ),
      td.MessageVideoNote(:final videoNote) => VideoNoteContent(
        message: m,
        note: videoNote,
        footer: overlayFooter,
      ),
      td.MessageAnimatedEmoji(:final emoji) => BigEmojiContent(emoji: emoji, footer: footer),
      _ => GenericContent(
        icon: genericIcon(m.content),
        title: Display.preview(context.read<TelegramCache>(), m),
        color: textColor,
        mutedColor: mutedColor,
        footer: footer,
      ),
    };
  }
}
