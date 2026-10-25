import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../core/storage/app_preferences.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/auth/domain/auth_step.dart';
import '../features/chat_info/data/chat_info_repository.dart';
import '../features/chats/presentation/widgets/chat_row_extensions.dart';
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
