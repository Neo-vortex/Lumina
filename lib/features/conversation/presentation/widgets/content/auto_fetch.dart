import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../../core/telegram/auto_download_gate.dart';
import '../../../../../core/telegram/download_registry.dart';
import '../../../../../core/telegram/file_store.dart';
import '../../../../../core/telegram/video_files.dart';

/// Starts the downloads Settings → Auto-download allows for [messages] when
/// they first show: videos, files, voice and video messages and music.
/// Photos and GIFs decide in their own widgets; everything else keeps its
/// tap-to-download ring.
class AutoFetch extends StatefulWidget {
  const AutoFetch({super.key, required this.messages, required this.child});

  final List<td.Message> messages;
  final Widget child;

  /// How much of a large video "Preload larger videos" fetches.
  static const preloadBytes = 1024 * 1024;

  @override
  State<AutoFetch> createState() => _AutoFetchState();
}

class _AutoFetchState extends State<AutoFetch> {
  static (td.File, MediaKind)? _target(td.MessageContent c) => switch (c) {
    td.MessageVideo() => (VideoFiles.pick(c), MediaKind.videos),
    td.MessageDocument(:final document) => (document.document, MediaKind.files),
    td.MessageVoiceNote(:final voiceNote) => (voiceNote.voice, MediaKind.voice),
    td.MessageVideoNote(:final videoNote) => (videoNote.video, MediaKind.videoMessages),
    td.MessageAudio(:final audio) => (audio.audio, MediaKind.music),
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    for (final m in widget.messages) {
      if (_target(m.content) case (final file, final kind)) {
        final gate = AutoDownloadGate.of(context);
        final store = context.read<FileStore>();
        final f = store[file.id] ?? file;
        final local = f.local;
        if (local.isDownloadingCompleted || local.isDownloadingActive || !local.canBeDownloaded) continue;
        final size = f.size > 0 ? f.size : f.expectedSize;
        if (gate.allows(chatId: m.chatId, media: kind, size: size)) {
          store.download(f.id, priority: 2).ignore();
          DownloadRegistry.of(context).track(f, m);
        } else if (kind == MediaKind.videos && gate.preloadLargeVideos && local.downloadedPrefixSize == 0) {
          store.requestRange(f.id, 0, limit: AutoFetch.preloadBytes, priority: 1).ignore();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
