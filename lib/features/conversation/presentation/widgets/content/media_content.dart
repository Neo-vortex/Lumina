import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../../core/telegram/auto_download_gate.dart';

import '../../../../../core/telegram/display.dart';
import '../../../../../core/telegram/download_registry.dart';
import '../../../../../core/telegram/video_files.dart';
import '../../../../../core/telegram/widgets/file_progress.dart';
import '../../../../../core/storage/app_preferences.dart';
import '../../../../../core/telegram/widgets/formatted_text_view.dart';
import '../../../../../core/telegram/widgets/inline_video.dart';
import '../../../../../core/telegram/widgets/looping_gif.dart';
import '../../../../../core/telegram/widgets/td_file_image.dart';
import '../../../../../core/theme/glow_colors.dart';
import '../../../../media/presentation/screens/media_viewer_screen.dart';
import '../../../../media/presentation/widgets/media_flight.dart';
import '../../../bloc/conversation_cubit.dart';
import '../forward_sheet.dart';

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
    // The copy Settings → Video quality picks (its size is what shows).
    media: VideoFiles.pick(c),
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
  MediaViewerScreen.open(
    context,
    messages,
    index: index,
    onOpened: (m) => cubit.openViewOnce(m).ignore(),
    onForward: (context, m) => showForwardSheet(context, fromChatId: m.chatId, messageIds: [m.id]),
  );
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
  var _gifPaused = false;
  final _flightKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    MediaFlight.register(widget.message.id, _flightKey);
  }

  @override
  void didUpdateWidget(MediaTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      MediaFlight.unregister(oldWidget.message.id, _flightKey);
      MediaFlight.register(widget.message.id, _flightKey);
    }
  }

  @override
  void dispose() {
    MediaFlight.unregister(widget.message.id, _flightKey);
    super.dispose();
  }

  /// Galleries (compact) always load; chat bubbles ask the gate.
  bool _allows(MediaKind kind, td.File f) =>
      widget.compact ||
      AutoDownloadGate.of(context)
          .allows(chatId: widget.message.chatId, media: kind, size: f.size > 0 ? f.size : f.expectedSize);

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final v = visualOf(m.content);
    if (v == null) return const SizedBox.shrink();
    final viewOnce = m.selfDestructType != null;
    final covered = (viewOnce || _hasSpoiler(m.content)) && !_revealed;
    // GIFs loop silently in place, like Telegram; no big player.
    final gif = m.content is td.MessageAnimation && !covered;
    // Videos play in the bubble once downloaded.
    final inline = m.content is td.MessageVideo && !covered && !widget.compact && v.media != null;
    final image = gif
        ? LoopingGif(
            file: v.media!,
            thumbnail: v.file,
            minithumbnail: v.mini,
            paused: _gifPaused,
            autoDownload: _allows(MediaKind.gifs, v.media!),
          )
        : v.file != null
        ? TdFileImage(
            file: v.file!,
            // Video thumbnails are small and always load; photos follow
            // Settings → Auto-download (the ring downloads on tap).
            autoDownload: v.isVideo || _allows(MediaKind.photos, v.file!),
            placeholderBytes: Display.minithumbnail(v.mini),
            semanticLabel: v.isVideo ? 'Video' : 'Photo',
            progressive: !v.isVideo,
          )
        : (Display.minithumbnail(v.mini) != null
              ? Image.memory(Display.minithumbnail(v.mini)!, fit: BoxFit.cover)
              : Container(color: GlowColors.surfaceHigh));

    return GestureDetector(
      onTap: () {
        if (covered && !viewOnce) {
          setState(() => _revealed = true);
        } else if (gif) {
          // GIFs play in place; a tap pauses or resumes.
          setState(() => _gifPaused = !_gifPaused);
        } else {
          widget.onTap();
        }
      },
      // The viewer flies the picture to and from here; while it does, the
      // tile steps aside (no Hero: the tile is never remounted).
      child: ValueListenableBuilder<int?>(
        valueListenable: MediaFlight.hidden,
        builder: (context, hidden, child) => Opacity(opacity: hidden == m.id ? 0 : 1, child: child),
        child: Stack(
          key: _flightKey,
          fit: StackFit.expand,
          children: [
            if (covered)
              ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22), child: image)
            else if (inline)
              // Downloaded: plays right here (small play and mute buttons);
              // the rest of the tile still opens the viewer.
              FileBuilder(
                file: v.media!,
                builder: (context, f) => f.isDownloaded && f.local.path.isNotEmpty
                    ? InlineVideo(
                        path: f.local.path,
                        still: image,
                        autoplay: context.read<AppPreferences>().autoplayVideos,
                      )
                    : Stack(fit: StackFit.expand, children: [image, const Center(child: _PlayBadge())]),
              )
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
            else if (v.isVideo && !widget.compact && !inline && (!gif || _gifPaused))
              const Center(child: _PlayBadge()),
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
              Center(
                child: TransferRing(
                  file: v.file!,
                  showSize: true,
                  onStart: (f) => DownloadRegistry.of(context).track(f, widget.message),
                ),
              ),
            if (!covered && v.isVideo && v.media != null && !widget.compact)
              Positioned(
                right: 8,
                top: 8,
                child: TransferRing(
                  file: v.media!,
                  size: 36,
                  showSize: true,
                  onStart: (f) => DownloadRegistry.of(context).track(f, widget.message),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The big round play button over a video that isn't downloaded yet.
class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) => Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.black.withValues(alpha: 0.5),
      // A ring, not a blurred glow: one blur per video on screen cost
      // a pass every scroll frame.
      border: Border.all(color: GlowColors.cyan.withValues(alpha: 0.55), width: 1.5),
    ),
    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
  );
}

/// Album rendered as a "media cluster": up to four overlapping, slightly
/// fanned rounded cards, the last showing "+N" (spec §9.2). Tapping a card
/// opens the gallery at that item.
class MediaCluster extends StatefulWidget {
  const MediaCluster({super.key, required this.messages, required this.textColor, required this.footer});

  final List<td.Message> messages;
  final Color textColor;
  final Widget footer;

  @override
  State<MediaCluster> createState() => _MediaClusterState();
}

class _MediaClusterState extends State<MediaCluster> {
  /// The card last opened in the viewer comes to the front of the fan and
  /// stays there: the close flight lands on top instead of dropping under
  /// the cards stacked over it.
  int? _front;

  @override
  void initState() {
    super.initState();
    MediaFlight.hidden.addListener(_onFlight);
  }

  @override
  void dispose() {
    MediaFlight.hidden.removeListener(_onFlight);
    super.dispose();
  }

  void _onFlight() {
    final id = MediaFlight.hidden.value;
    if (id != null && id != _front && widget.messages.any((m) => m.id == id)) setState(() => _front = id);
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages;
    final textColor = widget.textColor;
    final footer = widget.footer;
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
                  for (final i in [
                    for (var i = shown.length - 1; i >= 0; i--)
                      if (shown[i].id != _front) i,
                    ...[
                      for (var i = 0; i < shown.length; i++)
                        if (shown[i].id == _front) i,
                    ],
                  ])
                    Positioned(
                      key: ValueKey(shown[i].id),
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
