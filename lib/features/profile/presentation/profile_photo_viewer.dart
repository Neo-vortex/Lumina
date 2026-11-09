import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/platform/system_channel.dart';
import '../../../core/telegram/display.dart';
import '../../../core/telegram/file_store.dart';
import '../../../core/telegram/widgets/td_file_image.dart';
import '../../media/presentation/screens/media_viewer_screen.dart';

/// Profile photos full screen: page between them, pinch or double-tap to
/// zoom (the media viewer's smooth zoom), save the current one to the
/// gallery, swipe down to close.
class ProfilePhotoViewer extends StatefulWidget {
  const ProfilePhotoViewer({super.key, required this.photos, this.initial = 0, this.save});

  final List<td.ChatPhoto> photos;
  final int initial;

  /// Saves a downloaded file to the gallery (tests swap it).
  final Future<bool> Function(String path)? save;

  /// The header photo flies into place (a Hero on the photo's id) while the
  /// black fades in; closing flies it back.
  static Route<void> route(List<td.ChatPhoto> photos, int initial) => PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) => ProfilePhotoViewer(photos: photos, initial: initial),
    transitionsBuilder: (_, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );

  static String heroTag(td.ChatPhoto p) => 'profile-photo-${p.id}';

  @override
  State<ProfilePhotoViewer> createState() => _ProfilePhotoViewerState();
}

class _ProfilePhotoViewerState extends State<ProfilePhotoViewer> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  final _zooms = <int, TransformationController>{};

  @override
  void dispose() {
    _pages.dispose();
    for (final z in _zooms.values) {
      z.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final sizes = widget.photos[_index].sizes;
    if (sizes.isEmpty) return;
    final file = context.read<FileStore>()[sizes.last.photo.id] ?? sizes.last.photo;
    if (!file.local.isDownloadingCompleted) {
      messenger.showSnackBar(const SnackBar(content: Text('Still loading the photo')));
      return;
    }
    final ok = await (widget.save ?? (p) => const SystemChannel().saveToGallery(p))(file.local.path);
    messenger.showSnackBar(SnackBar(content: Text(ok ? 'Saved to gallery' : 'Couldn\'t save the photo')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black54,
      foregroundColor: Colors.white,
      title: Text('${_index + 1} / ${widget.photos.length}'),
      actions: [
        IconButton(tooltip: 'Save to gallery', icon: const Icon(Icons.download_rounded), onPressed: _save),
      ],
    ),
    extendBodyBehindAppBar: true,
    body: Dismissible(
      key: const ValueKey('profile-photo-viewer'),
      direction: DismissDirection.down,
      onDismissed: (_) => Navigator.of(context).pop(),
      child: PageView.builder(
        controller: _pages,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final p = widget.photos[i];
          final zoom = _zooms.putIfAbsent(i, TransformationController.new);
          return DoubleTapZoom(
            controller: zoom,
            child: InteractiveViewer(
              transformationController: zoom,
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: p.sizes.isEmpty
                      ? const SizedBox.shrink()
                      : Hero(
                          tag: ProfilePhotoViewer.heroTag(p),
                          child: TdFileImage(
                            file: p.sizes.last.photo,
                            fit: BoxFit.contain,
                            fullResolution: true,
                            placeholderBytes: Display.minithumbnail(p.minithumbnail),
                            semanticLabel: 'Profile photo ${i + 1}',
                          ),
                        ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
