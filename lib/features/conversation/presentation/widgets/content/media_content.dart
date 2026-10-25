import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../../../core/telegram/display.dart';
import '../../../../../core/telegram/widgets/file_progress.dart';
import '../../../../../core/telegram/widgets/formatted_text_view.dart';
import '../../../../../core/telegram/widgets/td_file_image.dart';
import '../../../../../core/theme/glow_colors.dart';
import '../../../../media/presentation/screens/media_viewer_screen.dart';
import '../../../bloc/conversation_cubit.dart';

const _maxMediaHeight = 340.0;

/// Visual (thumbnail) data of a photo/video/GIF message.
({td.File? file, td.Minithumbnail? mini, int w, int h, bool isVideo, int duration, td.File? media})? visualOf(
  td.MessageContent c,
) => switch (c) {
  td.MessagePhoto(:final photo) => () {
    final s = _displaySize(photo);
    return (
      file: s?.photo,
      mini: photo.minithumbnail,
      w: s?.width ?? 1,
      h: s?.height ?? 1,
      isVideo: false,
      duration: 0,
      media: null,
    );
  }(),
  td.MessageVideo(:final video) => (
    file: video.thumbnail?.file,
    mini: video.minithumbnail,
    w: video.width,
    h: video.height,
    isVideo: true,
    duration: video.duration,
    media: video.video,
  ),
  td.MessageAnimation(:final animation) => (
    file: animation.thumbnail?.file,
    mini: animation.minithumbnail,
    w: animation.width,
    h: animation.height,
    isVideo: true,
    duration: 0,
    media: animation.animation,
  ),
  _ => null,
};

/// The bubble shows a mid-size photo; the viewer loads the largest.
td.PhotoSize? _displaySize(td.Photo photo) {
  if (photo.sizes.isEmpty) return null;
  final sorted = [...photo.sizes]..sort((a, b) => a.width.compareTo(b.width));
  return sorted.firstWhere((s) => s.width >= 640, orElse: () => sorted.last);
}

td.FormattedText? captionOf(td.MessageContent c) => switch (c) {
  td.MessagePhoto(:final caption) ||
  td.MessageVideo(:final caption) ||
  td.MessageAnimation(:final caption) => caption.text.isEmpty ? null : caption,
  _ => null,
};

bool _hasSpoiler(td.MessageContent c) => switch (c) {
  td.MessagePhoto(:final hasSpoiler) ||
  td.MessageVideo(:final hasSpoiler) ||
  td.MessageAnimation(:final hasSpoiler) => hasSpoiler,
  _ => false,
};

/// Single photo / video / GIF with caption and footer.
class VisualContent extends StatelessWidget {
  const VisualContent({super.key, required this.message, required this.textColor, required this.footer});

  final td.Message message;
  final Color textColor;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final caption = captionOf(message.content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final v = visualOf(message.content)!;
            final width = c.maxWidth.isFinite ? c.maxWidth : 280.0;
            final ratio = v.h == 0 ? 1.0 : (v.w / v.h).clamp(0.5, 2.2);
            final height = math.min(width / ratio, _maxMediaHeight);
            return SizedBox(
              width: width,
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MediaTile(message: message, onTap: () => openMessageMedia(context, [message], 0)),
                  if (caption == null) Positioned(right: 8, bottom: 6, child: _Pill(child: footer)),
                ],
              ),
            );
          },
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 7),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              children: [
                FormattedTextView(caption, style: TextStyle(color: textColor, fontSize: 15, height: 1.35)),
                footer,
              ],
            ),
          ),
      ],
    );
  }
}

/// Opens the gallery; marks view-once content as opened.
void openMessageMedia(BuildContext context, List<td.Message> messages, int index) {
  final cubit = context.read<ConversationCubit>();
  MediaViewerScreen.open(context, messages, index: index, onOpened: (m) => cubit.openViewOnce(m).ignore());
}

/// One photo/video thumbnail with play badge, transfer ring, spoiler and
/// view-once cover.
class MediaTile extends StatefulWidget {
  const MediaTile({super.key, required this.message, required this.onTap, this.compact = false});

  final td.Message message;
  final VoidCallback onTap;
  final bool compact;

  @override
  State<MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<MediaTile> {
  var _revealed = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final v = visualOf(m.content);
    if (v == null) return const SizedBox.shrink();
    final viewOnce = m.selfDestructType != null;
    final covered = (viewOnce || _hasSpoiler(m.content)) && !_revealed;
    final image = v.file != null
        ? TdFileImage(
            file: v.file!,
            placeholderBytes: Display.minithumbnail(v.mini),
            semanticLabel: v.isVideo ? 'Video' : 'Photo',
          )
        : (Display.minithumbnail(v.mini) != null
              ? Image.memory(Display.minithumbnail(v.mini)!, fit: BoxFit.cover)
              : Container(color: GlowColors.surfaceHigh));

    return GestureDetector(
      onTap: () {
        if (covered && !viewOnce) {
          setState(() => _revealed = true);
        } else {
          widget.onTap();
        }
      },
      child: Hero(
        tag: 'media-${m.id}',
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (covered)
              ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22), child: image)
            else
              image,
            if (covered)
              Center(
                child: _Pill(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        viewOnce ? Icons.looks_one_rounded : Icons.visibility_off_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(viewOnce ? 'View once' : 'Spoiler', style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              )
            else if (v.isVideo && !widget.compact)
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.5),
                    boxShadow: glow(GlowColors.cyan, intensity: 0.3),
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                ),
              ),
            if (v.isVideo && !covered)
              Positioned(
                left: 8,
                top: 8,
                child: _Pill(
                  child: Text(
                    v.duration > 0 ? Display.duration(v.duration) : 'GIF',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            if (!covered && !v.isVideo && v.file != null && !widget.compact)
              Center(child: TransferRing(file: v.file!)),
            if (!covered && v.isVideo && v.media != null && !widget.compact)
              Positioned(right: 8, top: 8, child: TransferRing(file: v.media!, size: 36)),
          ],
        ),
      ),
    );
  }
}

/// Album rendered as a "media cluster": up to four overlapping, slightly
/// fanned rounded cards, the last showing "+N" (spec §9.2). Tapping a card
/// opens the gallery at that item.
class MediaCluster extends StatelessWidget {
  const MediaCluster({super.key, required this.messages, required this.textColor, required this.footer});

  final List<td.Message> messages;
  final Color textColor;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final visuals = messages.where((m) => visualOf(m.content) != null).toList();
    final shown = visuals.take(4).toList();
    final extra = visuals.length - shown.length;
    final caption = messages.map((m) => captionOf(m.content)).whereType<td.FormattedText>().firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final width = c.maxWidth.isFinite ? c.maxWidth : 280.0;
            const height = 260.0;
            final cardW = width * (shown.length == 1 ? 1 : 0.62);
            final step = shown.length <= 1 ? 0.0 : (width - cardW) / (shown.length - 1);
            return SizedBox(
              width: width,
              height: height,
              child: Stack(
                children: [
                  for (var i = shown.length - 1; i >= 0; i--)
                    Positioned(
                      left: step * i,
                      top: 10.0 + (i.isEven ? 0 : 14),
                      width: cardW,
                      height: height - 34,
                      child: Transform.rotate(
                        angle: (i - (shown.length - 1) / 2) * 0.045,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: GlowColors.background, width: 2),
                            boxShadow: glow(GlowColors.violet, intensity: 0.15),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              MediaTile(
                                message: shown[i],
                                compact: true,
                                onTap: () => openMessageMedia(context, visuals, i),
                              ),
                              if (i == shown.length - 1 && extra > 0)
                                IgnorePointer(
                                  child: Container(
                                    color: Colors.black45,
                                    alignment: Alignment.center,
                                    child: Text(
                                      '+$extra',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (caption == null) Positioned(right: 8, bottom: 4, child: _Pill(child: footer)),
                ],
              ),
            );
          },
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 7),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              children: [
                FormattedTextView(caption, style: TextStyle(color: textColor, fontSize: 15, height: 1.35)),
                footer,
              ],
            ),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(10),
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: Colors.white),
      child: IconTheme(
        data: const IconThemeData(color: Colors.white),
        child: child,
      ),
    ),
  );
}
