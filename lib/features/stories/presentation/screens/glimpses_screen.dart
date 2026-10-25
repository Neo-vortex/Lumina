import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/telegram/widgets/td_file_image.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../data/stories_repository.dart';
import '../../domain/story_feed.dart';
import '../widgets/story_halo.dart';
import 'saved_stories_screen.dart';
import 'story_viewer_screen.dart';

/// "Glimpses": every active story as a vertical stream of tall preview
/// cards, unseen first. Reached from the compose orb, not a top bar.
class GlimpsesScreen extends StatelessWidget {
  const GlimpsesScreen({super.key, this.onPost});

  /// Opens the post flow; null hides the button (bots, or posting blocked).
  final void Function(BuildContext context)? onPost;

  static Route<void> route({void Function(BuildContext context)? onPost}) =>
      MaterialPageRoute(builder: (_) => GlimpsesScreen(onPost: onPost));

  @override
  Widget build(BuildContext context) {
    final repo = context.read<StoriesRepository>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Glimpses'),
        actions: [
          IconButton(
            tooltip: 'Story history',
            onPressed: () => Navigator.of(context).push(SavedStoriesScreen.route()),
            icon: const Icon(Icons.bookmarks_rounded),
          ),
        ],
      ),
      floatingActionButton: onPost == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: GlowColors.violetDeep,
              onPressed: () => onPost!(context),
              icon: const Icon(Icons.add_a_photo_rounded),
              label: const Text('Post story'),
            ),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final feed = repo.feed;
          if (repo.hidden) {
            return const Center(
              child: Text('Stories are hidden in Settings', style: TextStyle(color: GlowColors.textMuted)),
            );
          }
          if (feed.isEmpty) {
            return RefreshIndicator(
              onRefresh: repo.loadMain,
              child: ListView(
                children: const [
                  SizedBox(height: 160),
                  Icon(Icons.blur_on_rounded, size: 56, color: GlowColors.textMuted),
                  SizedBox(height: 12),
                  Center(
                    child: Text('No stories right now', style: TextStyle(color: GlowColors.textMuted)),
                  ),
                ],
              ),
            );
          }
          final ids = [for (final s in feed) s.chatId];
          return RefreshIndicator(
            onRefresh: repo.loadMain,
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                childAspectRatio: 9 / 15,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: feed.length,
              itemBuilder: (context, i) => _GlimpseCard(
                active: feed[i],
                onTap: () => Navigator.of(context).push(StoryViewerScreen.route(ids, initial: i)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GlimpseCard extends StatelessWidget {
  const _GlimpseCard({required this.active, required this.onTap});

  final td.ChatActiveStories active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final chat = cache.chats[active.chatId];
    final unseen = StoryFeed.hasUnseen(active);
    final latest = active.stories.last;
    return Semantics(
      button: true,
      label: '${chat?.title ?? 'Story'}, ${active.stories.length} stories${unseen ? ', new' : ''}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: GlowColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: unseen ? GlowColors.violet : GlowColors.outline,
              width: unseen ? 1.6 : 1,
            ),
            boxShadow: unseen ? const [BoxShadow(color: Color(0x557440E0), blurRadius: 18)] : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Preview(key: ValueKey(latest.storyId), chatId: active.chatId, storyId: latest.storyId),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.center,
                      colors: [Color(0xDD000000), Color(0x00000000)],
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Row(
                    children: [
                      StoryHalo(
                        size: 32,
                        unseen: unseen,
                        child: chat == null
                            ? const SizedBox.square(dimension: 32)
                            : ChatAvatar.chat(chat, size: 32),
                      ),
                      const SizedBox(width: 8),
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
                              '${Display.relativeTime(DateTime.fromMillisecondsSinceEpoch(latest.date * 1000), DateTime.now())}'
                              '${active.stories.length > 1 ? ' · ${active.stories.length}' : ''}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatefulWidget {
  const _Preview({super.key, required this.chatId, required this.storyId});

  final int chatId;
  final int storyId;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  td.Story? _story;

  @override
  void initState() {
    super.initState();
    context.read<StoriesRepository>().story(widget.chatId, widget.storyId).then((s) {
      if (mounted) setState(() => _story = s);
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final (file, mini) = switch (_story?.content) {
      td.StoryContentPhoto(:final photo) => (
        photo.sizes.isEmpty
            ? null
            : photo.sizes.reduce((a, b) => (a.width - 480).abs() <= (b.width - 480).abs() ? a : b).photo,
        photo.minithumbnail,
      ),
      td.StoryContentVideo(:final video) => (video.thumbnail?.file, video.minithumbnail),
      _ => (null, null),
    };
    if (file == null) {
      final bytes = Display.minithumbnail(mini);
      return bytes == null
          ? const ColoredBox(color: GlowColors.surfaceHigh)
          : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
    }
    return TdFileImage(file: file, placeholderBytes: Display.minithumbnail(mini), priority: 4);
  }
}
