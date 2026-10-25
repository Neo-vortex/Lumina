import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../data/saved_stories_store.dart';
import '../../domain/saved_story.dart';
import 'saved_story_viewer_screen.dart';

/// Everyone whose stories the user has kept, newest first.
class SavedStoriesScreen extends StatelessWidget {
  const SavedStoriesScreen({super.key});

  static Route<void> route() => MaterialPageRoute(builder: (_) => const SavedStoriesScreen());

  @override
  Widget build(BuildContext context) {
    final store = context.read<SavedStoriesStore>();
    final cache = context.read<TelegramCache>();
    return Scaffold(
      appBar: AppBar(title: const Text('Story history')),
      body: FutureBuilder(
        future: store.ready(),
        builder: (context, _) => ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final posters = store.posters;
            if (posters.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Stories you save, or auto-save from someone, stay here after they expire.\n'
                    'Tap the bookmark while watching a story.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: GlowColors.textMuted),
                  ),
                ),
              );
            }
            return ListView.builder(
              itemCount: posters.length,
              itemBuilder: (context, i) {
                final p = posters[i];
                final chat = cache.chats[p.chatId];
                return ListTile(
                  leading: chat == null
                      ? CircleAvatar(child: Text(p.title.isEmpty ? '?' : p.title.characters.first))
                      : ChatAvatar.chat(chat, size: 44),
                  title: Text(chat?.title ?? p.title),
                  subtitle: Text(
                    '${p.count} ${p.count == 1 ? 'story' : 'stories'} · last ${DateFormat.yMMMd().format(p.latest.posted)}',
                  ),
                  trailing: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 40,
                      height: 64,
                      child: Image.file(
                        File(store.pathOf(p.latest.thumb)),
                        fit: BoxFit.cover,
                        cacheWidth: 120,
                      ),
                    ),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(chat?.title ?? p.title)),
                        body: CustomScrollView(slivers: savedHistorySlivers(context, p.chatId)),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// The per-poster history: an auto-save switch and every saved story,
/// grouped by month. Used as the chat info "Story history" tab.
List<Widget> savedHistorySlivers(BuildContext context, int chatId) => [
  SliverToBoxAdapter(child: _HistoryHeader(chatId: chatId)),
  _HistoryGrid(chatId: chatId),
  const SliverToBoxAdapter(child: SizedBox(height: 120)),
];

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.chatId});

  final int chatId;

  @override
  Widget build(BuildContext context) {
    final store = context.read<SavedStoriesStore>();
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => SwitchListTile(
        value: store.autoSaves(chatId),
        onChanged: (v) => store.setAutoSave(chatId, v),
        secondary: const Icon(Icons.bookmarks_rounded, color: GlowColors.amber),
        title: const Text('Auto-save their stories'),
        subtitle: const Text(
          'New stories are kept on this phone when they appear, without marking them as viewed. '
          'Stories with saving turned off are skipped.',
        ),
      ),
    );
  }
}

class _HistoryGrid extends StatelessWidget {
  const _HistoryGrid({required this.chatId});

  final int chatId;

  @override
  Widget build(BuildContext context) {
    final store = context.read<SavedStoriesStore>();
    return FutureBuilder(
      future: store.ready(),
      builder: (context, _) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final items = store.forChat(chatId);
          if (items.isEmpty) {
            return const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No saved stories yet. Tap the bookmark while watching one of their stories.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: GlowColors.textMuted),
                ),
              ),
            );
          }
          // Month headers between runs of tiles.
          final groups = <String, List<int>>{};
          for (var i = 0; i < items.length; i++) {
            (groups[DateFormat.yMMMM().format(items[i].posted)] ??= []).add(i);
          }
          return SliverMainAxisGroup(
            slivers: [
              for (final MapEntry(key: month, value: indexes) in groups.entries) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      month.toUpperCase(),
                      style: const TextStyle(
                        color: GlowColors.violet,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 130,
                      childAspectRatio: 9 / 16,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                    ),
                    itemCount: indexes.length,
                    itemBuilder: (context, j) => _Tile(
                      entry: items[indexes[j]],
                      path: store.pathOf(items[indexes[j]].thumb),
                      onTap: () =>
                          Navigator.of(context)
                              .push(SavedStoryViewerScreen.route(items, initial: indexes[j])),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.entry, required this.path, required this.onTap});

  final SavedStory entry;
  final String path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${entry.isVideo ? 'Video' : 'Photo'} story from ${DateFormat.yMMMd().format(entry.posted)}',
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(path),
              fit: BoxFit.cover,
              cacheWidth: 300,
              errorBuilder: (_, _, _) => const ColoredBox(color: GlowColors.surfaceHigh),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Color(0xAA000000), Color(0x00000000)],
                ),
              ),
            ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Text(
                DateFormat.MMMd().format(entry.posted),
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            if (entry.isVideo)
              const Positioned(
                right: 6,
                top: 6,
                child: Icon(Icons.play_circle_rounded, color: Colors.white, size: 18),
              ),
            if (entry.auto)
              const Positioned(
                left: 6,
                top: 6,
                child: Icon(Icons.bolt_rounded, color: GlowColors.amber, size: 16),
              ),
          ],
        ),
      ),
    ),
  );
}
