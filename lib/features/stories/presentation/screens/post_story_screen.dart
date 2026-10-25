import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../media/presentation/widgets/video_player_view.dart';
import '../../data/stories_repository.dart';

/// Pick a photo or video, add a caption, choose who sees it, post.
///
/// [chatId] is the poster: the user's own (Saved Messages) chat, or a
/// channel they administer.
class PostStoryScreen extends StatefulWidget {
  const PostStoryScreen({super.key, required this.chatId});

  final int chatId;

  /// Picks media first so an aborted pick never shows an empty editor.
  static Future<void> open(BuildContext context, {required int chatId}) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = context.read<StoriesRepository>();
    final blocked = await repo.cannotPost(chatId);
    if (blocked != null) {
      messenger.showSnackBar(SnackBar(content: Text(blocked)));
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => PostStoryScreen(chatId: chatId)));
  }

  @override
  State<PostStoryScreen> createState() => _PostStoryScreenState();
}

class _PostStoryScreenState extends State<PostStoryScreen> {
  final _caption = TextEditingController();
  String? _path;
  var _isVideo = false;
  var _audience = StoryAudience.everyone;
  var _keepOnProfile = false;
  var _protect = false;
  double? _progress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick(camera: false));
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool camera, bool video = false}) async {
    final picker = ImagePicker();
    final XFile? f;
    if (camera) {
      f = video
          ? await picker.pickVideo(source: ImageSource.camera)
          : await picker.pickImage(source: ImageSource.camera);
    } else {
      f = await picker.pickMedia(requestFullMetadata: false);
    }
    if (!mounted) return;
    if (f == null) {
      if (_path == null) Navigator.pop(context);
      return;
    }
    final lower = f.path.toLowerCase();
    setState(() {
      _path = f!.path;
      _isVideo = const ['.mp4', '.mov', '.mkv', '.webm', '.3gp', '.avi'].any(lower.endsWith);
    });
  }

  Future<void> _post() async {
    final path = _path;
    if (path == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _progress = 0);
    final error = await context.read<StoriesRepository>().post(
      chatId: widget.chatId,
      path: path,
      isVideo: _isVideo,
      caption: _caption.text.trim(),
      audience: _audience,
      keepOnProfile: _keepOnProfile,
      protect: _protect,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    if (error != null) {
      setState(() => _progress = null);
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('Posting your story…')));
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    final busy = _progress != null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('New story'),
        actions: [
          IconButton(
            tooltip: 'Take photo',
            onPressed: busy ? null : () => _pick(camera: true),
            icon: const Icon(Icons.photo_camera_rounded),
          ),
          IconButton(
            tooltip: 'Record video',
            onPressed: busy ? null : () => _pick(camera: true, video: true),
            icon: const Icon(Icons.videocam_rounded),
          ),
          IconButton(
            tooltip: 'Choose from gallery',
            onPressed: busy ? null : () => _pick(camera: false),
            icon: const Icon(Icons.photo_library_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: path == null
                ? const Center(child: CircularProgressIndicator(color: GlowColors.cyan))
                : Center(
                    child: AspectRatio(
                      aspectRatio: 9 / 16,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: ColoredBox(
                          color: GlowColors.backgroundDeep,
                          child: _isVideo
                              ? VideoPlayerView(
                                  key: ValueKey(path),
                                  source: path,
                                  isLocalFile: true,
                                  loop: true,
                                  showControls: false,
                                )
                              : Image.file(File(path), fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _caption,
                    enabled: !busy,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(hintText: 'Add a caption…'),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<StoryAudience>(
                    segments: [
                      for (final a in StoryAudience.values) ButtonSegment(value: a, label: Text(a.label)),
                    ],
                    selected: {_audience},
                    onSelectionChanged: busy ? null : (s) => setState(() => _audience = s.first),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _keepOnProfile,
                          onChanged: busy ? null : (v) => setState(() => _keepOnProfile = v ?? false),
                          title: const Text('Keep on profile'),
                        ),
                      ),
                      Expanded(
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _protect,
                          onChanged: busy ? null : (v) => setState(() => _protect = v ?? false),
                          title: const Text('No screenshots'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: GlowColors.violetDeep,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: busy || path == null ? null : _post,
                    icon: busy
                        ? SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              value: _progress == 0 ? null : _progress,
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(busy ? (_isVideo ? 'Preparing video…' : 'Posting…') : 'Share for 24 hours'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
