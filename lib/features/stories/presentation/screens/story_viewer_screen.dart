import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../../core/media/tdlib_stream_server.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/telegram/widgets/td_file_image.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';
import '../../../media/presentation/widgets/video_player_view.dart';
import '../../data/stories_repository.dart';
import '../../domain/story_feed.dart';
import '../widgets/story_halo.dart';

/// Full-screen story viewer.
///
/// Progress is a ring around the poster's avatar at the bottom left rather
/// than bars along the top. Tap right/left: next/previous story; swipe
/// sideways: next/previous person; swipe down: close; swipe up: reply;
/// hold: pause.
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({super.key, required this.chatIds, this.initial = 0});

  final List<int> chatIds;
  final int initial;

  static Route<void> route(List<int> chatIds, {int initial = 0}) => PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black,
    transitionDuration: Motion.standard,
    pageBuilder: (_, _, _) => StoryViewerScreen(chatIds: chatIds, initial: initial),
    transitionsBuilder: (_, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(
        scale: Tween(begin: 0.94, end: 1.0).animate(CurvedAnimation(parent: a, curve: Motion.enter)),
        child: child,
      ),
    ),
  );

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _current = widget.initial;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_current + 1 >= widget.chatIds.length) {
      Navigator.of(context).maybePop();
    } else {
      _pages.nextPage(duration: Motion.standard, curve: Motion.move);
    }
  }

  void _previous() {
    if (_current > 0) _pages.previousPage(duration: Motion.standard, curve: Motion.move);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: PageView.builder(
      controller: _pages,
      itemCount: widget.chatIds.length,
      onPageChanged: (i) => setState(() => _current = i),
      itemBuilder: (context, i) => _ChatStories(
        key: ValueKey(widget.chatIds[i]),
        chatId: widget.chatIds[i],
        active: i == _current,
        onFinished: _next,
        onBeforeFirst: _previous,
      ),
    ),
  );
}

class _ChatStories extends StatefulWidget {
  const _ChatStories({
    super.key,
    required this.chatId,
    required this.active,
    required this.onFinished,
    required this.onBeforeFirst,
  });

  final int chatId;
  final bool active;
  final VoidCallback onFinished;
  final VoidCallback onBeforeFirst;

  @override
  State<_ChatStories> createState() => _ChatStoriesState();
}

class _ChatStoriesState extends State<_ChatStories> with SingleTickerProviderStateMixin {
  static const _photoDuration = Duration(seconds: 6);
  static const _quickReactions = ['❤️', '🔥', '😂', '😮', '😢', '👏'];

  late final StoriesRepository _repo = context.read<StoriesRepository>();
  late final _timer = AnimationController(vsync: this, duration: _photoDuration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _advance();
    });

  List<td.StoryInfo> _infos = const [];
  var _index = 0;
  td.Story? _story;
  String? _error;
  double _videoProgress = 0;
  ({String source, bool local})? _video;
  var _held = false;
  var _replying = false;
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();

  bool get _paused => _held || _replying || !widget.active;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_ChatStories oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _syncTimer();
      if (widget.active) _markOpen();
    }
  }

  @override
  void dispose() {
    _closeCurrent();
    _timer.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final active = _repo.of(widget.chatId) ?? await _repo.refresh(widget.chatId);
      if (!mounted) return;
      if (active.stories.isEmpty) return widget.onFinished();
      _infos = active.stories;
      await _show(StoryFeed.startIndex(active));
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load stories');
    }
  }

  Future<void> _show(int index) async {
    _closeCurrent();
    _timer.stop();
    setState(() {
      _index = index;
      _story = null;
      _video = null;
      _videoProgress = 0;
    });
    final info = _infos[index];
    final story = await _repo.story(widget.chatId, info.storyId);
    if (!mounted || _index != index) return;
    ({String source, bool local})? video;
    if (story.content case td.StoryContentVideo(video: td.StoryVideo(video: final f))) {
      if (f.local.isDownloadingCompleted && f.local.path.isNotEmpty) {
        video = (source: f.local.path, local: true);
      } else {
        final url = await context.read<TdStreamServer>().urlFor(f, mimeType: 'video/mp4');
        if (!mounted || _index != index) return;
        video = (source: url.toString(), local: false);
      }
    }
    setState(() {
      _story = story;
      _video = video;
    });
    _markOpen();
    _timer.value = 0;
    _syncTimer();
  }

  void _markOpen() {
    final s = _story;
    if (s != null && widget.active) _repo.open(s.senderChatId, s.id).ignore();
  }

  void _closeCurrent() {
    final s = _story;
    if (s != null) _repo.close(s.senderChatId, s.id).ignore();
  }

  void _syncTimer() {
    final isPhoto = _story != null && _story!.content is! td.StoryContentVideo;
    if (isPhoto && !_paused) {
      _timer.forward();
    } else {
      _timer.stop();
    }
  }

  void _advance() {
    if (_index + 1 < _infos.length) {
      _show(_index + 1);
    } else {
      widget.onFinished();
    }
  }

  void _back() {
    if (_index > 0) {
      _show(_index - 1);
    } else {
      widget.onBeforeFirst();
    }
  }

  void _hold(bool held) {
    setState(() => _held = held);
    _syncTimer();
  }

  void _openReply() {
    final s = _story;
    if (s == null || !s.canBeReplied) return;
    setState(() => _replying = true);
    _syncTimer();
    _replyFocus.requestFocus();
  }

  void _closeReply() {
    _replyFocus.unfocus();
    setState(() => _replying = false);
    _syncTimer();
  }

  Future<void> _sendReply() async {
    final s = _story;
    final text = _reply.text.trim();
    if (s == null || text.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    _reply.clear();
    _closeReply();
    try {
      await _repo.reply(s.senderChatId, s.id, text);
      messenger.showSnackBar(const SnackBar(content: Text('Reply sent')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not send the reply')));
    }
  }

  Future<void> _react(String? emoji) async {
    final s = _story;
    if (s == null) return;
    HapticFeedback.lightImpact();
    try {
      await _repo.react(s.senderChatId, s.id, emoji);
      final fresh = await _repo.story(s.senderChatId, s.id);
      if (mounted && _story?.id == s.id) {
        setState(
          () => _story = fresh.copyWith(
            chosenReactionType: emoji == null ? null : td.ReactionTypeEmoji(emoji: emoji),
          ),
        );
      }
    } catch (_) {}
    if (_replying) _closeReply();
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final chat = cache.chats[widget.chatId];
    final story = _story;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        if (_replying) return _closeReply();
        final w = MediaQuery.sizeOf(context).width;
        d.localPosition.dx > w / 3 ? _advance() : _back();
      },
      onLongPressStart: (_) => _hold(true),
      onLongPressEnd: (_) => _hold(false),
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v > 300) {
          if (_replying) {
            _closeReply();
          } else {
            Navigator.of(context).maybePop();
          }
        } else if (v < -300) {
          _openReply();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_error != null)
            Center(
              child: Text(_error!, style: const TextStyle(color: GlowColors.textMuted)),
            )
          else if (story == null)
            const Center(child: CircularProgressIndicator(color: GlowColors.cyan))
          else
            IgnorePointer(child: _content(story)),
          // Soft scrim so the caption and controls stay legible on bright media.
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment(0, 0.2),
                  colors: [Color(0xCC000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: MediaQuery.paddingOf(context).top + 8,
            child: IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
          if (_held)
            const Center(child: Icon(Icons.pause_circle_filled_rounded, size: 64, color: Colors.white38)),
          Positioned(
            left: 12,
            right: 12,
            bottom: MediaQuery.paddingOf(context).bottom + 12,
            child: AnimatedBuilder(
              animation: _timer,
              builder: (context, _) => _bottom(
                cache,
                chat,
                story,
                story?.content is td.StoryContentVideo ? _videoProgress : _timer.value,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(td.Story story) {
    switch (story.content) {
      case td.StoryContentPhoto(:final photo):
        final best = photo.sizes.isEmpty ? null : photo.sizes.reduce((a, b) => a.width >= b.width ? a : b);
        if (best == null) return const SizedBox.shrink();
        return TdFileImage(
          file: best.photo,
          fit: BoxFit.contain,
          priority: 32,
          placeholderBytes: Display.minithumbnail(photo.minithumbnail),
        );
      case td.StoryContentVideo(:final video):
        final v = _video;
        if (v == null) return const Center(child: CircularProgressIndicator(color: GlowColors.cyan));
        return VideoPlayerView(
          key: ValueKey(story.id),
          source: v.source,
          isLocalFile: v.local,
          aspectRatio: video.height == 0 ? null : video.width / video.height,
          showControls: false,
          paused: _paused,
          onProgress: (position, duration, ended) {
            if (!mounted || _story?.id != story.id) return;
            final total = duration.inMilliseconds > 0
                ? duration.inMilliseconds
                : (video.duration * 1000).round();
            final p = total == 0 ? 0.0 : position.inMilliseconds / total;
            if (ended) {
              _advance();
            } else if ((p - _videoProgress).abs() > 0.005) {
              setState(() => _videoProgress = p);
            }
          },
        );
      default:
        return const Center(
          child: Text('This story type is not supported yet', style: TextStyle(color: GlowColors.textMuted)),
        );
    }
  }

  Widget _bottom(TelegramCache cache, td.Chat? chat, td.Story? story, double progress) {
    final caption = story?.caption.text ?? '';
    final date = story == null ? null : DateTime.fromMillisecondsSinceEpoch(story.date * 1000);
    final views = story?.interactionInfo?.viewCount;
    final mine = story != null && story.canGetInteractions;
    final chosen = switch (story?.chosenReactionType) {
      td.ReactionTypeEmoji(:final emoji) => emoji,
      _ => null,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (caption.isNotEmpty && !_replying)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              caption,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35),
            ),
          ),
        AnimatedSwitcher(
          duration: Motion.micro,
          child: _replying
              ? _replyBar(chosen)
              : Row(
                  key: const ValueKey('info'),
                  children: [
                    StoryProgressRing(
                      size: 44,
                      count: _infos.length,
                      index: _index,
                      progress: progress,
                      child: chat == null
                          ? const SizedBox.square(dimension: 44)
                          : ChatAvatar.chat(chat, size: 44),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            chat?.title ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            [
                              if (date != null) Display.relativeTime(date, DateTime.now()),
                              '${_index + 1} of ${_infos.length}',
                              if (mine && views != null) '$views views',
                              if (story?.privacySettings is td.StoryPrivacySettingsCloseFriends)
                                'close friends',
                            ].join(' · '),
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (story != null && !mine) ...[
                      IconButton(
                        tooltip: chosen == null ? 'Like' : 'Remove reaction',
                        onPressed: () => _react(chosen == null ? '❤️' : null),
                        icon: chosen == null
                            ? const Icon(Icons.favorite_border_rounded, color: Colors.white)
                            : Text(chosen, style: const TextStyle(fontSize: 22)),
                      ),
                      if (story.canBeReplied)
                        IconButton(
                          tooltip: 'Reply',
                          onPressed: _openReply,
                          icon: const Icon(Icons.reply_rounded, color: Colors.white),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _replyBar(String? chosen) => Column(
    key: const ValueKey('reply'),
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final e in _quickReactions)
            GestureDetector(
              onTap: () => _react(e == chosen ? null : e),
              child: AnimatedScale(
                scale: e == chosen ? 1.3 : 1,
                duration: Motion.micro,
                child: Text(e, style: const TextStyle(fontSize: 30)),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _reply,
              focusNode: _replyFocus,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendReply(),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Reply privately…',
                filled: true,
                fillColor: Colors.white12,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: GlowColors.violetDeep),
            tooltip: 'Send',
            onPressed: _sendReply,
            icon: const Icon(Icons.send_rounded),
          ),
        ],
      ),
    ],
  );
}
