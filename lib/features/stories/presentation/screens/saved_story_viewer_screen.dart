import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../media/presentation/widgets/video_player_view.dart';
import '../../data/saved_stories_store.dart';
import '../../domain/saved_story.dart';

/// Plays saved copies from the history: swipe between them, delete.
class SavedStoryViewerScreen extends StatefulWidget {
  const SavedStoryViewerScreen({super.key, required this.items, this.initial = 0});

  final List<SavedStory> items;
  final int initial;

  static Route<void> route(List<SavedStory> items, {int initial = 0}) => MaterialPageRoute(
    builder: (_) => SavedStoryViewerScreen(items: items, initial: initial),
  );

  @override
  State<SavedStoryViewerScreen> createState() => _SavedStoryViewerScreenState();
}

class _SavedStoryViewerScreenState extends State<SavedStoryViewerScreen> {
  late final _items = [...widget.items];
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final entry = _items[_index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlowColors.surfaceHigh,
        title: const Text('Remove from history?'),
        content: const Text('The saved copy on this phone is deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: GlowColors.coral)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<SavedStoriesStore>().delete(entry);
    if (!mounted) return;
    setState(() {
      _items.removeAt(_index);
      if (_index >= _items.length) _index = _items.length - 1;
    });
    if (_items.isEmpty) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<SavedStoriesStore>();
    final entry = _items.isEmpty ? null : _items[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: entry == null
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.chatTitle, style: const TextStyle(fontSize: 16)),
                  Text(
                    'Posted ${DateFormat.yMMMd().add_Hm().format(entry.posted)}',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
        actions: [
          IconButton(tooltip: 'Remove', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: _items.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final e = _items[i];
          return Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: e.isVideo
                      ? (i == _index
                            ? VideoPlayerView(
                                key: ValueKey(e.file),
                                source: store.pathOf(e.file),
                                isLocalFile: true,
                                loop: true,
                              )
                            : Image.file(File(store.pathOf(e.thumb)), fit: BoxFit.contain))
                      : InteractiveViewer(child: Image.file(File(store.pathOf(e.file)), fit: BoxFit.contain)),
                ),
              ),
              if (e.caption.isNotEmpty)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.paddingOf(context).bottom + 20,
                  child: Text(
                    e.caption,
                    style: const TextStyle(color: Colors.white, shadows: [Shadow(blurRadius: 6)]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
