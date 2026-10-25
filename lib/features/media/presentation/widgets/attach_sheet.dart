import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/media/ffmpeg_service.dart';
import '../../../../core/theme/glow_colors.dart';

/// Where the user wants to pick media from; returns local file paths.
Future<List<String>> pickAttachments(BuildContext context, FfmpegService ffmpeg) async {
  final source = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: GlowColors.surfaceHigh,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _Source(
              icon: Icons.photo_library_rounded,
              label: 'Gallery',
              color: GlowColors.cyan,
              value: 'gallery',
            ),
            _Source(
              icon: Icons.photo_camera_rounded,
              label: 'Photo',
              color: GlowColors.violet,
              value: 'camera',
            ),
            _Source(icon: Icons.videocam_rounded, label: 'Video', color: GlowColors.coral, value: 'video'),
            _Source(icon: Icons.attach_file_rounded, label: 'File', color: GlowColors.amber, value: 'file'),
          ],
        ),
      ),
    ),
  );
  final picker = ImagePicker();
  switch (source) {
    case 'gallery':
      final files = await picker.pickMultipleMedia(limit: 10, requestFullMetadata: false);
      return [for (final f in files) f.path];
    case 'camera':
      final f = await picker.pickImage(source: ImageSource.camera, imageQuality: 92);
      return [if (f != null) f.path];
    case 'video':
      final f = await picker.pickVideo(source: ImageSource.camera);
      return [if (f != null) f.path];
    case 'file':
      final files = await FilePicker.pickFiles(type: FileType.any);
      final paths = <String>[];
      for (final f in files) {
        final direct = f.path;
        if (direct != null) {
          paths.add(direct);
        } else {
          // content:// URI: copy into our cache so TDLib can read it.
          final ext = f.extension ?? 'bin';
          final dest = await ffmpeg.tempPath(ext);
          await f.xFile.saveTo(dest);
          paths.add(dest);
        }
      }
      return paths;
    default:
      return const [];
  }
}

class _Source extends StatelessWidget {
  const _Source({required this.icon, required this.label, required this.color, required this.value});

  final IconData icon;
  final String label;
  final Color color;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.pop(context, value),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.15),
                  border: Border.all(color: color.withValues(alpha: 0.7)),
                  boxShadow: glow(color, intensity: 0.3),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
