import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/media/tdlib_stream_server.dart';
import '../../../../core/storage/app_preferences.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/file_store.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/formatted_text_view.dart';
import '../../../../core/telegram/widgets/td_file_image.dart';
import '../widgets/video_player_view.dart';

/// Biggest photo size (what the viewer shows).
td.PhotoSize? largestSize(td.Photo photo) => photo.sizes.isEmpty
    ? null
    : photo.sizes.reduce((a, b) => a.width * a.height >= b.width * b.height ? a : b);

/// Full-screen gallery over photos and videos (spec §9.2 media cluster
/// target): swipe between items, pinch-zoom photos, hero transition from
/// the bubble, VLC playback for videos (streamed when not downloaded).
class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({super.key, required this.messages, required this.initialIndex, this.onOpened});

  final List<td.Message> messages;
  final int initialIndex;

  /// View-once / self-destructing content must be marked opened.
  final void Function(td.Message message)? onOpened;

  static Future<void> open(
    BuildContext context,
    List<td.Message> messages, {
    int index = 0,
    void Function(td.Message)? onOpened,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) =>
            MediaViewerScreen(messages: messages, initialIndex: index, onOpened: onOpened),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  var _chrome = true;
  final _zoom = TransformationController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _markOpened(widget.messages[_index]);
  }

  void _markOpened(td.Message m) {
    if (m.selfDestructType != null) widget.onOpened?.call(m);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pages.dispose();
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final m = widget.messages[_index];
    final caption = switch (m.content) {
      td.MessagePhoto(:final caption) ||
      td.MessageVideo(:final caption) ||
      td.MessageAnimation(:final caption) => caption,
      _ => null,
    };
    return Scaffold(
      backgroundColor: Colors.black,
      body: Dismissible(
        key: const ValueKey('viewer'),
        direction: DismissDirection.vertical,
        onDismissed: (_) => Navigator.pop(context),
        child: Stack(
          children: [
            PageView.builder(
              controller: _pages,
              itemCount: widget.messages.length,
              onPageChanged: (i) {
                setState(() => _index = i);
                _zoom.value = Matrix4.identity();
                _markOpened(widget.messages[i]);
              },
              itemBuilder: (context, i) => _Page(
                message: widget.messages[i],
                zoom: _zoom,
                onTap: () => setState(() => _chrome = !_chrome),
                onChrome: (visible) => setState(() => _chrome = visible),
              ),
            ),
            AnimatedOpacity(
              opacity: _chrome ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_chrome,
                child: SafeArea(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Close',
                            icon: const Icon(Icons.close_rounded, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.isOutgoing ? 'You' : Display.senderName(cache, m.senderId),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  Display.listTime(Display.messageDate(m), DateTime.now()),
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          if (widget.messages.length > 1)
                            Padding(
                              padding: const EdgeInsets.only(right: 16),
                              child: Text(
                                '${_index + 1} / ${widget.messages.length}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      if (caption != null && caption.text.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Color(0xCC000000), Color(0x00000000)],
                            ),
                          ),
                          child: FormattedTextView(
                            caption,
                            style: const TextStyle(color: Colors.white, fontSize: 15),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.message, required this.zoom, required this.onTap, required this.onChrome});

  final td.Message message;
  final TransformationController zoom;
  final VoidCallback onTap;

  /// Videos handle their own taps; they report their controls' visibility.
  final ValueChanged<bool> onChrome;

  @override
  Widget build(BuildContext context) {
    switch (message.content) {
      case td.MessagePhoto(:final photo):
        final size = largestSize(photo);
        if (size == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: onTap,
          onDoubleTapDown: (d) {
            final zoomed = zoom.value.getMaxScaleOnAxis() > 1.01;
            zoom.value = zoomed
                ? Matrix4.identity()
                : (Matrix4.identity()
                    ..translateByDouble(-d.localPosition.dx, -d.localPosition.dy, 0, 1)
                    ..scaleByDouble(2.5, 2.5, 1, 1));
          },
          onDoubleTap: () {},
          child: InteractiveViewer(
            transformationController: zoom,
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: Hero(
                tag: 'media-${message.id}',
                child: AspectRatio(
                  aspectRatio: size.height == 0 ? 1 : size.width / size.height,
                  child: TdFileImage(
                    file: size.photo,
                    fit: BoxFit.contain,
                    priority: 32,
                    placeholderBytes: Display.minithumbnail(photo.minithumbnail),
                    semanticLabel: 'Photo',
                  ),
                ),
              ),
            ),
          ),
        );
      case td.MessageVideo(:final video):
        return _VideoPage(
          file: video.video,
          mime: video.mimeType,
          width: video.width,
          height: video.height,
          onChrome: onChrome,
        );
      case td.MessageAnimation(:final animation):
        return _VideoPage(
          file: animation.animation,
          mime: animation.mimeType,
          width: animation.width,
          height: animation.height,
          loop: true,
          onChrome: onChrome,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Resolves a video to a local path or a loopback stream URL, then plays.
class _VideoPage extends StatefulWidget {
  const _VideoPage({
    required this.file,
    required this.mime,
    required this.width,
    required this.height,
    required this.onChrome,
    this.loop = false,
  });

  final td.File file;
  final String mime;
  final int width;
  final int height;
  final ValueChanged<bool> onChrome;
  final bool loop;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  ({String source, bool local})? _source;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  Future<void> _resolve() async {
    if (_source != null) return;
    final files = context.read<FileStore>();
    final f = files[widget.file.id] ?? widget.file;
    if (f.local.isDownloadingCompleted && f.local.path.isNotEmpty) {
      setState(() => _source = (source: f.local.path, local: true));
      return;
    }
    final url = await context.read<TdStreamServer>().urlFor(
      f,
      mimeType: widget.mime.isEmpty ? 'video/mp4' : widget.mime,
    );
    if (mounted) setState(() => _source = (source: url.toString(), local: false));
  }

  @override
  Widget build(BuildContext context) {
    final s = _source;
    if (s == null) return const Center(child: CircularProgressIndicator());
    return VideoPlayerView(
      source: s.source,
      isLocalFile: s.local,
      aspectRatio: widget.height == 0 ? null : widget.width / widget.height,
      loop: widget.loop,
      prefs: context.read<AppPreferences>(),
      onControlsVisibilityChanged: widget.onChrome,
      fileId: widget.file.id,
    );
  }
}
