import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/tdlib/td_client.dart';
import '../../../core/telegram/file_store.dart';
import '../../../core/telegram/widgets/td_file_image.dart';
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
      BackdropImage(:final file?) => TdFileImage(file: file, fit: BoxFit.cover),
      BackdropImage(:final fileId?) => _FileById(id: fileId),
      BackdropImage(:final path?) => Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox(),
      ),
      _ => const SizedBox(),
    };
    if (backdrop.blur > 0) {
      layer = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: backdrop.blur, sigmaY: backdrop.blur, tileMode: TileMode.decal),
        child: layer,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: ClipRect(child: layer)),
        ColoredBox(
          key: const ValueKey('backdrop-dim'),
          color: Colors.black.withValues(alpha: backdrop.dim),
        ),
        child,
      ],
    );
  }
}

/// A gallery wallpaper remembered by its TDLib file id.
class _FileById extends StatefulWidget {
  const _FileById({required this.id});
  final int id;

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
    builder: (context, snap) =>
        snap.data == null ? const SizedBox() : TdFileImage(file: snap.data!, fit: BoxFit.cover),
  );
}
