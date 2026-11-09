import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../core/storage/app_preferences.dart';
import '../core/telegram/telegram_cache.dart';
import '../core/telegram/widgets/chat_avatar.dart';
import '../core/theme/glow_colors.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/auth/domain/auth_step.dart';
import '../features/chat_info/data/chat_info_repository.dart';
import '../features/chat_info/presentation/chat_info_extensions.dart';
import '../features/chats/presentation/widgets/chat_row_extensions.dart';
import '../features/stories/presentation/screens/saved_stories_screen.dart';
import '../features/stories/data/stories_repository.dart';
import '../features/stories/domain/story_feed.dart';
import '../features/stories/presentation/screens/glimpses_screen.dart';
import '../features/stories/presentation/screens/post_story_screen.dart';
import '../features/stories/presentation/screens/story_viewer_screen.dart';
import '../features/stories/presentation/widgets/story_halo.dart';

/// Story halos on timeline avatars (spec §5.4: no top bar).
class AppChatRowExtensions extends ChatRowExtensions {
  AppChatRowExtensions({required this.stories, required this.prefs});

  final StoriesRepository stories;
  final AppPreferences prefs;

  @override
  Listenable get listenable => Listenable.merge([stories, prefs.changes]);

  @override
  Widget avatar(BuildContext context, td.Chat chat, Widget avatar, double size) {
    final active = prefs.hideStories ? null : stories.of(chat.id);
    if (active == null) return super.avatar(context, chat, avatar, size);
    return StoryHalo(
      size: size,
      unseen: StoryFeed.hasUnseen(active),
      onTap: () {
        final ids = [for (final s in stories.feed) s.chatId];
        final at = ids.indexOf(chat.id);
        Navigator.of(context)
            .push(at < 0 ? StoryViewerScreen.route([chat.id]) : StoryViewerScreen.route(ids, initial: at));
      },
      child: avatar,
    );
  }
}

/// Opens the post flow as the signed-in user (their Saved Messages chat).
Future<void> postStoryAsMe(BuildContext context) async {
  final me = switch (context.read<AuthBloc>().state.step) {
    AuthReady(:final me) => me,
    _ => null,
  };
  if (me == null) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final self = await context.read<ChatInfoRepository>().privateChat(me.id);
    if (context.mounted) await PostStoryScreen.open(context, chatId: self.id);
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Stories are not available right now')));
  }
}

void openGlimpses(BuildContext context) =>
    Navigator.of(context).push(GlimpsesScreen.route(onPost: postStoryAsMe));

bool storiesVisible(BuildContext context) => !context.read<AppPreferences>().hideStories;

/// Chat info → "Story history" for people and channels.
class AppChatInfoExtensions extends ChatInfoExtensions {
  const AppChatInfoExtensions({required this.prefs});

  final AppPreferences prefs;

  @override
  List<ChatInfoTab> tabs(BuildContext context, td.Chat chat) {
    if (prefs.hideStories) return const [];
    final self = switch (context.read<AuthBloc>().state.step) {
      AuthReady(:final me) => me.id,
      _ => null,
    };
    final eligible = switch (chat.type) {
      td.ChatTypePrivate(:final userId) => userId != self,
      td.ChatTypeSupergroup() => true,
      _ => false,
    };
    if (!eligible) return const [];
    return [
      ChatInfoTab(
        label: 'Story history',
        icon: Icons.bookmarks_rounded,
        slivers: (context) => savedHistorySlivers(context, chat.id),
      ),
    ];
  }
}

/// People's stories in a row under the chat list title: yours first (or a
/// "+" to post one), then everyone else, unseen first. Hidden when nobody
/// has a story or the user hid stories.
class StoryStrip extends StatelessWidget {
  const StoryStrip({super.key, required this.stories, required this.prefs});

  final StoriesRepository stories;
  final AppPreferences prefs;

  static const _avatar = 54.0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([stories, prefs.changes]),
    builder: (context, _) {
      final me = switch (context.read<AuthBloc>().state.step) {
        AuthReady(:final me, :final capabilities) when !capabilities.isBot => me.id,
        _ => null,
      };
      final feed = prefs.hideStories || me == null ? const <td.ChatActiveStories>[] : stories.feed;
      final others = [
        for (final s in feed)
          if (s.chatId != me) s,
      ];
      final mine = me == null ? null : stories.of(me);
      return AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: others.isEmpty && mine == null
            ? const SizedBox(width: double.infinity)
            : SizedBox(
                height: 92,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _item(
                      context,
                      chatId: me!,
                      label: 'Your story',
                      active: mine,
                      onTap: mine == null
                          ? () => postStoryAsMe(context)
                          : () => Navigator.of(context).push(StoryViewerScreen.route([me])),
                    ),
                    for (var i = 0; i < others.length; i++)
                      _item(
                        context,
                        chatId: others[i].chatId,
                        active: others[i],
                        onTap: () => Navigator.of(context)
                            .push(StoryViewerScreen.route([for (final s in others) s.chatId], initial: i)),
                      ),
                  ],
                ),
              ),
      );
    },
  );

  Widget _item(
    BuildContext context, {
    required int chatId,
    required td.ChatActiveStories? active,
    required VoidCallback onTap,
    String? label,
  }) {
    final chat = context.read<TelegramCache>().chats[chatId];
    final name = label ?? (chat?.title.split(' ').first ?? '');
    final avatar = chat == null
        ? const CircleAvatar(radius: _avatar / 2, backgroundColor: GlowColors.surfaceHigh)
        : ChatAvatar.chat(chat, size: _avatar);
    return Semantics(
      button: true,
      label: active == null ? 'Post a story' : '$name, story',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(
          width: 68,
          child: Column(
            children: [
              const SizedBox(height: 4),
              if (active == null)
                // Your avatar with a "+" to post.
                GestureDetector(
                  onTap: onTap,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Padding(padding: const EdgeInsets.all(4), child: avatar),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: GlowColors.active,
                            border: Border.all(color: GlowColors.background, width: 2),
                          ),
                          child: const Icon(Icons.add_rounded, size: 15, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                )
              else
                StoryHalo(size: _avatar, unseen: StoryFeed.hasUnseen(active), onTap: onTap, child: avatar),
              const SizedBox(height: 4),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: GlowColors.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
