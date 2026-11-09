import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/tdlib/td_client.dart';
import '../../../core/telegram/file_store.dart';
import '../../../core/telegram/widgets/file_progress.dart';
import '../../../core/theme/glow_colors.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../../core/widgets/glow_background.dart';
import '../domain/chat_backdrop.dart';

/// Draws a chat's backdrop behind [child]: Lumina's glow, a wallpaper image
/// or a colour fill, blurred and dimmed as set. Static: no frames at idle.
class ChatBackdropView extends StatelessWidget {
  const ChatBackdropView({super.key, required this.backdrop, required this.child});

  final ChatBackdrop backdrop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spec = backdrop.spec;
    if (spec is BackdropGlow) return GlowBackground(child: child);
    if (spec is BackdropAurora) return AuroraBackground(drift: spec.drift, child: child);
    if (spec is BackdropPlain) return ColoredBox(color: GlowColors.background, child: child);
    final media = MediaQuery.of(context);
    final width = (media.size.width * media.devicePixelRatio).round();
    Widget baked(String path) => BakedBackdropImage(path: path, blur: backdrop.blur, decodeWidth: width);
    Widget layer = switch (spec) {
      BackdropFill(:final colors) => DecoratedBox(
        key: const ValueKey('backdrop-fill'),
        decoration: BoxDecoration(
          color: colors.length == 1 ? colors.first : null,
          gradient: colors.length > 1
              ? LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors)
              : null,
        ),
      ),
      BackdropImage(:final file?) => FileBuilder(
        file: file,
        builder: (context, f) => f.isDownloaded ? baked(f.local.path) : _Fetch(file: f),
      ),
      BackdropImage(:final fileId?) => _FileById(id: fileId, builder: baked),
      BackdropImage(:final path?) => baked(path),
      _ => const SizedBox(),
    };
    // Fills are cheap; images are pre-blurred, so nothing blurs per frame.
    if (backdrop.blur > 0 && spec is BackdropFill) {
      layer = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: backdrop.blur, sigmaY: backdrop.blur, tileMode: TileMode.decal),
        child: layer,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        // A new background fades in over the old one.
        RepaintBoundary(
          child: ClipRect(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (current, previous) =>
                  Stack(fit: StackFit.expand, children: [...previous, ?current]),
              child: KeyedSubtree(key: ValueKey(_identity(spec, backdrop.blur)), child: layer),
            ),
          ),
        ),
        TweenAnimationBuilder<double>(
          tween: Tween(end: backdrop.dim),
          duration: const Duration(milliseconds: 450),
          builder: (context, dim, _) => ColoredBox(
            key: const ValueKey('backdrop-dim'),
            color: Colors.black.withValues(alpha: dim),
          ),
        ),
        child,
      ],
    );
  }

  /// What the background is, so the same one doesn't animate on every rebuild.
  static String _identity(BackdropSpec spec, double blur) => switch (spec) {
    BackdropFill(:final colors) => 'fill:${colors.map((c) => c.toARGB32()).join(',')}:$blur',
    BackdropImage(:final file?) => 'file:${file.id}:$blur',
    BackdropImage(:final fileId?) => 'id:$fileId:$blur',
    BackdropImage(:final path?) => 'path:$path:$blur',
    _ => 'none',
  };
}

/// A gallery wallpaper remembered by its TDLib file id.
class _FileById extends StatefulWidget {
  const _FileById({required this.id, required this.builder});
  final int id;
  final Widget Function(String path) builder;

  @override
  State<_FileById> createState() => _FileByIdState();
}

class _FileByIdState extends State<_FileById> {
  late final Future<td.File?> _file = () async {
    final known = context.read<FileStore>()[widget.id];
    if (known != null) return known;
    try {
      return await context.read<TdClient>().invoke<td.File>(td.GetFile(fileId: widget.id));
    } catch (_) {
      return null;
    }
  }();

  @override
  Widget build(BuildContext context) => FutureBuilder<td.File?>(
    future: _file,
    builder: (context, snap) => snap.data == null
        ? const SizedBox()
        : FileBuilder(
            file: snap.data!,
            builder: (context, f) => f.isDownloaded ? widget.builder(f.local.path) : _Fetch(file: f),
          ),
  );
}

/// Starts a wallpaper download once.
class _Fetch extends StatefulWidget {
  const _Fetch({required this.file});
  final td.File file;

  @override
  State<_Fetch> createState() => _FetchState();
}

class _FetchState extends State<_Fetch> {
  @override
  void initState() {
    super.initState();
    if (widget.file.local.canBeDownloaded && !widget.file.local.isDownloadingActive) {
      context.read<FileStore>().download(widget.file.id, priority: 8).ignore();
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// A wallpaper decoded at screen width and, if [blur] > 0, blurred once
/// into a bitmap. Cached across chats, so returning to a chat shows it at
/// once (no black flash) and scrolling never re-blurs it.
class BakedBackdropImage extends StatefulWidget {
  const BakedBackdropImage({super.key, required this.path, required this.blur, required this.decodeWidth});

  final String path;
  final double blur;
  final int decodeWidth;

  static final _cache = <String, ui.Image>{};

  @override
  State<BakedBackdropImage> createState() => _BakedBackdropImageState();
}

class _BakedBackdropImageState extends State<BakedBackdropImage> {
  ui.Image? _image;

  String get _key => '${widget.path}|${widget.blur}|${widget.decodeWidth}';

  @override
  void initState() {
    super.initState();
    _image = BakedBackdropImage._cache[_key];
    if (_image == null) _bake();
  }

  @override
  void didUpdateWidget(BakedBackdropImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.blur != widget.blur || old.decodeWidth != widget.decodeWidth) {
      final cached = BakedBackdropImage._cache[_key];
      if (cached != null) {
        _image = cached;
      } else {
        _bake();
      }
    }
  }

  Future<void> _bake() async {
    final key = _key;
    try {
      final bytes = await File(widget.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: widget.decodeWidth);
      var image = (await codec.getNextFrame()).image;
      if (widget.blur > 0) {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawImage(
          image,
          Offset.zero,
          Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
        );
        final blurred = await recorder.endRecording().toImage(image.width, image.height);
        image.dispose();
        image = blurred;
      }
      // A few wallpapers at most; keep the newest.
      final cache = BakedBackdropImage._cache;
      if (cache.length > 4) cache.remove(cache.keys.first);
      cache[key] = image;
      if (mounted && key == _key) setState(() => _image = image);
    } catch (_) {
      // Unreadable file: the dim layer over the app background shows.
    }
  }

  @override
  Widget build(BuildContext context) =>
      _image == null ? const SizedBox() : RawImage(image: _image, fit: BoxFit.cover);
}
