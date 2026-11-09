import 'package:lumina_tdlib/api.dart' as td;

/// The content of a failed message, ready to be sent again as a new message
/// (for failures TDLib won't resend itself, e.g. the server rejected the
/// upload). Files are referred to by TDLib's own file ids, so nothing is
/// picked or copied again. Null for content that can't be rebuilt.
td.InputMessageContent? resendContent(td.Message m) {
  td.InputFile file(td.File f) => td.InputFileId(id: f.id);
  return switch (m.content) {
    td.MessageText(:final text) => td.InputMessageText(text: text, clearDraft: false),
    td.MessagePhoto(:final photo, :final caption, :final hasSpoiler, :final showCaptionAboveMedia)
        when photo.sizes.isNotEmpty =>
      td.InputMessagePhoto(
        photo: td.InputPhoto(
          photo: file(photo.sizes.last.photo),
          addedStickerFileIds: const [],
          width: photo.sizes.last.width,
          height: photo.sizes.last.height,
        ),
        caption: caption,
        showCaptionAboveMedia: showCaptionAboveMedia,
        hasSpoiler: hasSpoiler,
      ),
    td.MessageVideo(:final video, :final caption, :final hasSpoiler, :final showCaptionAboveMedia) =>
      td.InputMessageVideo(
        video: td.InputVideo(
          video: file(video.video),
          startTimestamp: 0,
          addedStickerFileIds: const [],
          duration: video.duration,
          width: video.width,
          height: video.height,
          supportsStreaming: video.supportsStreaming,
        ),
        caption: caption,
        showCaptionAboveMedia: showCaptionAboveMedia,
        hasSpoiler: hasSpoiler,
      ),
    td.MessageDocument(:final document, :final caption) => td.InputMessageDocument(
      document: td.InputDocument(document: file(document.document), disableContentTypeDetection: true),
      caption: caption,
    ),
    td.MessageVoiceNote(:final voiceNote, :final caption) => td.InputMessageVoiceNote(
      voiceNote: td.InputVoiceNote(
        voiceNote: file(voiceNote.voice),
        duration: voiceNote.duration,
        waveform: voiceNote.waveform,
      ),
      caption: caption,
    ),
    td.MessageAnimation(:final animation, :final caption, :final hasSpoiler, :final showCaptionAboveMedia) =>
      td.InputMessageAnimation(
        animation: td.InputAnimation(
          animation: file(animation.animation),
          addedStickerFileIds: const [],
          duration: animation.duration,
          width: animation.width,
          height: animation.height,
        ),
        caption: caption,
        showCaptionAboveMedia: showCaptionAboveMedia,
        hasSpoiler: hasSpoiler,
      ),
    td.MessageAudio(:final audio, :final caption) => td.InputMessageAudio(
      audio: td.InputAudio(
        audio: file(audio.audio),
        duration: audio.duration,
        title: audio.title,
        performer: audio.performer,
      ),
      caption: caption,
    ),
    _ => null,
  };
}
