import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/media/ffmpeg_service.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../media/presentation/widgets/video_player_view.dart';
import '../../data/stories_repository.dart';
import '../../domain/story_decoration.dart';
import '../widgets/decoration_sheets.dart';
import '../widgets/story_canvas.dart';

/// Pick a photo or video, decorate it (stickers, text, reaction / link /
/// location tags), add a caption, choose who sees it and who posts it.
///
/// [chatId] is the default poster: the user's own (Saved Messages) chat.
/// Channels and groups the user may post to are offered under "Post as".
class PostStoryScreen extends StatefulWidget {
  const PostStoryScreen({super.key, required this.chatId, this.initialPoster});

  final int chatId;

  /// Preselected poster when the user can't post personally.
  final int? initialPoster;

  static Future<void> open(BuildContext context, {required int chatId}) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = context.read<StoriesRepository>();
    final blocked = await repo.cannotPost(chatId);
    // The user may be unable to post personally but still post to a channel.
    final targets = blocked == null ? const <int>[] : await repo.postTargets();
    if (blocked != null && targets.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(blocked)));
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PostStoryScreen(chatId: chatId, initialPoster: blocked == null ? null : targets.first),
      ),
    );
  }

  @override
  State<PostStoryScreen> createState() => _PostStoryScreenState();
}

class _PostStoryScreenState extends State<PostStoryScreen> {
  static const _maxReactions = 5;
  static const _maxLinks = 3;

  late final StoriesRepository _repo = context.read<StoriesRepository>();
  final _caption = TextEditingController();
  final _decorations = <StoryDecoration>[];
  String? _path;
  var _isVideo = false;
  var _audience = StoryAudience.everyone;
  var _keepOnProfile = false;
  var _protect = false;
  double? _progress;
  late int _poster = widget.initialPoster ?? widget.chatId;
  List<int> _posters = const [];

  @override
  void initState() {
    super.initState();
    _posters = [widget.chatId];
    _repo.postTargets().then((ids) {
      if (mounted) setState(() => _posters = {widget.chatId, ...ids}.toList());
    });
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

  void _add(StoryDecoration? d) {
    if (d == null || !mounted) return;
    setState(() => _decorations.add(d));
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _addText() async {
    final t = TextSticker('');
    if (await editTextSticker(context, t) == true) _add(t);
  }

  Future<void> _editText(TextSticker t) async {
    final r = await editTextSticker(context, t);
    if (r == false) _decorations.remove(t);
    if (mounted) setState(() {});
  }

  Future<void> _addReaction() async {
    if (_decorations.whereType<ReactionTag>().length >= _maxReactions) {
      return _snack('Up to $_maxReactions reaction tags per story');
    }
    final e = await pickEmoji(context, emojis: reactionEmojis, title: 'Reaction tag');
    if (e != null) _add(ReactionTag(e));
  }

  Future<void> _addLink() async {
    if (_decorations.whereType<LinkTag>().length >= _maxLinks) {
      return _snack('Up to $_maxLinks links per story');
    }
    _add(await askLink(context));
  }

  Future<void> _post() async {
    final path = _path;
    if (path == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _progress = 0);
    String? overlay;
    final png = await renderOverlay(_decorations, _isVideo ? const Size(720, 1280) : const Size(1080, 1920));
    if (png != null && mounted) {
      overlay = await context.read<FfmpegService>().tempPath('png');
      await File(overlay).writeAsBytes(png);
    }
    if (!mounted) return;
    final error = await _repo.post(
      chatId: _poster,
      path: path,
      isVideo: _isVideo,
      caption: _caption.text.trim(),
      // Channel stories are always public.
      audience: _poster == widget.chatId ? _audience : StoryAudience.everyone,
      keepOnProfile: _keepOnProfile,
      protect: _protect,
      areas: [for (final d in _decorations) ?DecorationPainter.areaOf(d)],
      overlayPng: overlay,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (overlay != null) File(overlay).delete().ignore();
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
    final cache = context.read<TelegramCache>();
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
                : Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: IgnorePointer(
                            ignoring: busy,
                            child: StoryCanvas(
                              decorations: _decorations,
                              onChanged: () => setState(() {}),
                              onEditText: _editText,
                              media: _isVideo
                                  ? IgnorePointer(
                                      child: VideoPlayerView(
                                        key: ValueKey(path),
                                        source: path,
                                        isLocalFile: true,
                                        loop: true,
                                        showControls: false,
                                      ),
                                    )
                                  : Image.file(File(path), fit: BoxFit.contain),
                            ),
                          ),
                        ),
                      ),
                      // Decoration tools, a vertical rail beside the canvas.
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _Tool(Icons.text_fields_rounded, 'Text', busy ? null : _addText),
                          _Tool(
                            Icons.emoji_emotions_rounded,
                            'Sticker',
                            busy
                                ? null
                                : () async => _add(switch (await pickEmoji(context)) {
                                    final e? => EmojiSticker(e),
                                    null => null,
                                  }),
                          ),
                          _Tool(Icons.add_reaction_rounded, 'Reaction tag', busy ? null : _addReaction),
                          _Tool(Icons.link_rounded, 'Link', busy ? null : _addLink),
                          _Tool(
                            Icons.place_rounded,
                            'Location',
                            busy ? null : () async => _add(await askLocation(context)),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _caption,
                          enabled: !busy,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(hintText: 'Add a caption…'),
                        ),
                      ),
                      if (_posters.length > 1) ...[
                        const SizedBox(width: 10),
                        PopupMenuButton<int>(
                          tooltip: 'Post as',
                          enabled: !busy,
                          initialValue: _poster,
                          color: GlowColors.surfaceHigh,
                          onSelected: (id) async {
                            final blocked = await _repo.cannotPost(id);
                            if (!mounted) return;
                            if (blocked != null) return _snack(blocked);
                            setState(() => _poster = id);
                          },
                          itemBuilder: (_) => [
                            for (final id in _posters)
                              PopupMenuItem(
                                value: id,
                                child: Row(
                                  children: [
                                    if (cache.chats[id] case final c?) ChatAvatar.chat(c, size: 28),
                                    const SizedBox(width: 10),
                                    Text(id == widget.chatId ? 'Me' : cache.chats[id]?.title ?? 'Chat'),
                                  ],
                                ),
                              ),
                          ],
                          child: switch (cache.chats[_poster]) {
                            final c? => ChatAvatar.chat(
                              c,
                              size: 40,
                              glowIntensity: _poster == widget.chatId ? 0 : 0.5,
                            ),
                            null => const Icon(Icons.account_circle_rounded, size: 40),
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<StoryAudience>(
                    segments: [
                      for (final a in StoryAudience.values) ButtonSegment(value: a, label: Text(a.label)),
                    ],
                    selected: {_audience},
                    onSelectionChanged: busy || _poster != widget.chatId
                        ? null
                        : (s) => setState(() => _audience = s.first),
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
                    label: Text(
                      busy
                          ? (_isVideo ? 'Preparing video…' : 'Posting…')
                          : _poster == widget.chatId
                          ? 'Share for 24 hours'
                          : 'Post to ${cache.chats[_poster]?.title ?? 'channel'}',
                    ),
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

class _Tool extends StatelessWidget {
  const _Tool(this.icon, this.tooltip, this.onPressed);

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
    child: IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(backgroundColor: Colors.white12, foregroundColor: Colors.white),
      icon: Icon(icon),
    ),
  );
}
