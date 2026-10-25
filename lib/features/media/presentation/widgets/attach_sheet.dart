import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:handy_tdlib_next/api.dart' as td;
import 'package:image_picker/image_picker.dart';

import '../../../../core/media/ffmpeg_service.dart';
import '../../../../core/storage/app_preferences.dart';
import '../../../../core/theme/glow_colors.dart';
import 'location_sheet.dart';
import 'poll_composer.dart';

/// What the user picked in the attach hub.
sealed class AttachPick {
  const AttachPick();
}

/// Photos / videos / files to review in the send screen.
final class MediaPick extends AttachPick {
  const MediaPick(this.paths, {this.asFiles = false, this.music = false});
  final List<String> paths;

  /// Send photos and videos uncompressed, as documents.
  final bool asFiles;

  /// Audio files to send as music (with player and duration).
  final bool music;
}

final class VideoNotePick extends AttachPick {
  const VideoNotePick();
}

/// Ready-to-send content (location, poll).
final class ContentPick extends AttachPick {
  const ContentPick(this.content, {this.liveLocationSeconds = 0});
  final td.InputMessageContent content;

  /// > 0 for a live location the app must keep updating.
  final int liveLocationSeconds;
}

/// The host picks a contact (that lives in another feature).
final class ContactPick extends AttachPick {
  const ContactPick();
}

enum _Tile {
  file('File', Icons.description_rounded, GlowColors.amber, 'Documents, archives, anything'),
  location('Location', Icons.place_rounded, GlowColors.coral, 'Here, or live'),
  contact('Contact', Icons.person_rounded, GlowColors.cyan, 'Share someone'),
  poll('Poll', Icons.poll_rounded, GlowColors.violet, 'Ask the chat'),
  music('Music', Icons.music_note_rounded, GlowColors.magenta, 'Audio files'),
  roundVideo('Round video', Icons.radio_button_checked_rounded, GlowColors.teal, 'Quick video note');

  const _Tile(this.label, this.icon, this.color, this.hint);
  final String label;
  final IconData icon;
  final Color color;
  final String hint;
}

/// The attach hub (UX-34…37): two big actions for what people send most
/// (gallery via the system photo picker, no media permission needed;
/// camera), then compact tiles ordered by how often *this* user picks them,
/// and an "original quality" switch that sends photos and videos as files.
Future<AttachPick?> pickAttachments(
  BuildContext context,
  FfmpegService ffmpeg, {
  required AppPreferences prefs,
  bool allowVideoNote = true,
  bool allowPoll = true,
  bool allowContact = true,
}) async {
  final usage = _Usage(prefs);
  final tiles = [
    for (final t in _Tile.values)
      if ((t != _Tile.roundVideo || allowVideoNote) &&
          (t != _Tile.poll || allowPoll) &&
          (t != _Tile.contact || allowContact))
        t,
  ]..sort((a, b) => usage.of(b).compareTo(usage.of(a)));
  var asFiles = prefs.attachAsFiles;

  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: GlowColors.surfaceHigh,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 132,
                child: Row(
                  children: [
                    Expanded(
                      child: _HeroCard(
                        title: 'Gallery',
                        subtitle: 'Photos & videos',
                        icon: Icons.photo_library_rounded,
                        colors: const [GlowColors.teal, GlowColors.cyan],
                        onTap: () => Navigator.pop(context, 'gallery'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _HeroCard(
                        title: 'Camera',
                        subtitle: 'Tap: photo · hold: video',
                        icon: Icons.photo_camera_rounded,
                        colors: const [GlowColors.violetDeep, GlowColors.magenta],
                        onTap: () => Navigator.pop(context, 'camera'),
                        onLongPress: () {
                          HapticFeedback.mediumImpact();
                          Navigator.pop(context, 'video');
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.25,
                children: [
                  for (final t in tiles) _SmallTile(tile: t, onTap: () => Navigator.pop(context, t.name)),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                value: asFiles,
                onChanged: (v) => setState(() => asFiles = v),
                secondary: const Icon(Icons.high_quality_rounded, color: GlowColors.cyan),
                title: const Text('Original quality'),
                subtitle: const Text('Send photos and videos as files, uncompressed'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (choice == null) return null;
  prefs.attachAsFiles = asFiles;
  usage.bump(choice);
  if (!context.mounted) return null;
  final picker = ImagePicker();
  switch (choice) {
    case 'gallery':
      final files = await picker.pickMultipleMedia(limit: 10, requestFullMetadata: false);
      return files.isEmpty ? null : MediaPick([for (final f in files) f.path], asFiles: asFiles);
    case 'camera':
      final f = await picker.pickImage(source: ImageSource.camera, imageQuality: asFiles ? 100 : 92);
      return f == null ? null : MediaPick([f.path], asFiles: asFiles);
    case 'video':
      final f = await picker.pickVideo(source: ImageSource.camera);
      return f == null ? null : MediaPick([f.path], asFiles: asFiles);
    case 'roundVideo':
      return const VideoNotePick();
    case 'contact':
      return const ContactPick();
    case 'location':
      return showLocationSheet(context);
    case 'poll':
      return switch (await composePoll(context)) {
        final c? => ContentPick(c),
        null => null,
      };
    case 'file' || 'music':
      final music = choice == 'music';
      final files = await FilePicker.pickFiles(type: music ? FileType.audio : FileType.any);
      final paths = <String>[];
      for (final f in files) {
        final direct = f.path;
        if (direct != null) {
          paths.add(direct);
        } else {
          // content:// URI: copy into our cache so TDLib can read it.
          final dest = await ffmpeg.tempPath(f.extension ?? 'bin');
          await f.xFile.saveTo(dest);
          paths.add(dest);
        }
      }
      return paths.isEmpty ? null : MediaPick(paths, asFiles: true, music: music);
  }
  return null;
}

/// How often each tile was used, for adaptive ordering.
class _Usage {
  _Usage(this._prefs) {
    try {
      _counts.addAll((jsonDecode(_prefs.attachUsage) as Map).cast<String, int>());
    } catch (_) {}
  }

  final AppPreferences _prefs;
  final _counts = <String, int>{};

  // Ties keep the declared order (file, location, contact…).
  double of(_Tile t) => (_counts[t.name] ?? 0) - t.index / 100;

  void bump(String key) {
    _counts[key] = (_counts[key] ?? 0) + 1;
    _prefs.attachUsage = jsonEncode(_counts);
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onTap,
    this.onLongPress,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$title. $subtitle',
    excludeSemantics: true,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [for (final c in colors) c.withValues(alpha: 0.85)],
            ),
            boxShadow: glow(colors.last, intensity: 0.35),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Colors.white, size: 30),
                const Spacer(),
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SmallTile extends StatelessWidget {
  const _SmallTile({required this.tile, required this.onTap});

  final _Tile tile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${tile.label}. ${tile.hint}',
    excludeSemantics: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: GlowColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: tile.color.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, color: tile.color.withValues(alpha: 0.18)),
              child: Icon(tile.icon, color: tile.color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(tile.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    ),
  );
}
