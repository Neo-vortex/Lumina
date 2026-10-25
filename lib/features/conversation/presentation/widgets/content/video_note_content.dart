import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../../core/media/tdlib_stream_server.dart';
import '../../../../../core/telegram/display.dart';
import '../../../../../core/telegram/file_store.dart';
import '../../../../../core/telegram/widgets/td_file_image.dart';
import '../../../../../core/theme/glow_colors.dart';
import '../../../../media/presentation/widgets/video_player_view.dart';
import '../../../bloc/conversation_cubit.dart';

/// Round video message: thumbnail with a glowing ring; tap plays inline
/// (streamed if needed), tap again stops.
class VideoNoteContent extends StatefulWidget {
  const VideoNoteContent({super.key, required this.message, required this.note, required this.footer});

  final td.Message message;
  final td.VideoNote note;
  final Widget footer;

  @override
  State<VideoNoteContent> createState() => _VideoNoteContentState();
}

class _VideoNoteContentState extends State<VideoNoteContent> {
  ({String source, bool local})? _playing;

  Future<void> _toggle() async {
    if (_playing != null) {
      setState(() => _playing = null);
      return;
    }
    final files = context.read<FileStore>();
    final stream = context.read<TdStreamServer>();
    final f = files[widget.note.video.id] ?? widget.note.video;
    if (f.local.isDownloadingCompleted) {
      setState(() => _playing = (source: f.local.path, local: true));
    } else {
      final url = await stream.urlFor(f, mimeType: 'video/mp4');
      if (mounted) setState(() => _playing = (source: url.toString(), local: false));
    }
    if (!widget.message.isOutgoing && mounted) {
      context.read<ConversationCubit>().openViewOnce(widget.message).ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    const size = 210.0;
    final thumb = widget.note.thumbnail?.file;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: 'Video message, ${Display.duration(widget.note.duration)}',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: _toggle,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: GlowColors.cyan.withValues(alpha: 0.8), width: 2),
                  boxShadow: glow(GlowColors.cyan, intensity: _playing != null ? 0.9 : 0.3),
                ),
                child: ClipOval(
                  child: _playing != null
                      ? VideoPlayerView(
                          source: _playing!.source,
                          isLocalFile: _playing!.local,
                          aspectRatio: 1,
                          showControls: false,
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            if (thumb != null)
                              TdFileImage(
                                file: thumb,
                                placeholderBytes: Display.minithumbnail(widget.note.minithumbnail),
                              )
                            else
                              Container(color: GlowColors.surfaceHigh),
                            const Center(
                              child: Icon(Icons.play_arrow_rounded, size: 48, color: Colors.white),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          widget.footer,
        ],
      ),
    );
  }
}
