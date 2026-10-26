import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/widgets/animated_sticker.dart';
import '../../../core/telegram/widgets/looping_gif.dart';
import '../../../core/telegram/widgets/td_file_image.dart';
import '../../../core/theme/glow_colors.dart';
import '../data/emoji_data.dart';
import '../data/media_panel_repository.dart';

/// The composer's media panel, keyboard height so nothing jumps: glowing
/// Emoji · Stickers · GIFs tabs. Emoji insert into the draft ([onEmoji]);
/// stickers and GIFs send straight away ([onSent] after).
class MediaPanel extends StatefulWidget {
  const MediaPanel({
    super.key,
    required this.chatId,
    required this.height,
    required this.onEmoji,
    required this.onSent,
  });

  final int chatId;
  final double height;
  final ValueChanged<String> onEmoji;
  final VoidCallback onSent;

  @override
  State<MediaPanel> createState() => _MediaPanelState();
}

class _MediaPanelState extends State<MediaPanel> {
  var _tab = 0;
  static const _tabs = ['Emoji', 'Stickers', 'GIFs'];

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    height: widget.height,
    decoration: BoxDecoration(
      color: GlowColors.surface,
      border: Border(top: BorderSide(color: GlowColors.violet.withValues(alpha: 0.35))),
    ),
    child: Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _TabPill(
                    label: _tabs[i],
                    selected: i == _tab,
                    onTap: () => setState(() => _tab = i),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              _EmojiTab(onEmoji: widget.onEmoji),
              _tab == 1 ? _StickerTab(chatId: widget.chatId, onSent: widget.onSent) : const SizedBox.shrink(),
              _tab == 2 ? _GifTab(chatId: widget.chatId, onSent: widget.onSent) : const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TabPill extends StatelessWidget {
  const _TabPill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: selected ? GlowColors.violet.withValues(alpha: 0.2) : Colors.transparent,
        border: Border.all(color: selected ? GlowColors.violet : GlowColors.outline),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? GlowColors.violet : GlowColors.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _EmojiTab extends StatefulWidget {
  const _EmojiTab({required this.onEmoji});

  final ValueChanged<String> onEmoji;

  @override
  State<_EmojiTab> createState() => _EmojiTabState();
}

class _EmojiTabState extends State<_EmojiTab> {
  final _keys = [for (final _ in emojiCategories) GlobalKey()];
  late final _repo = context.read<MediaPanelRepository>();

  void _pick(String e) {
    _repo.useEmoji(e);
    widget.onEmoji(e);
  }

  Widget _grid(List<String> emoji) => SliverGrid(
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 44),
    delegate: SliverChildBuilderDelegate(
      (context, i) => InkResponse(
        radius: 22,
        onTap: () => _pick(emoji[i]),
        child: Center(child: Text(emoji[i], style: const TextStyle(fontSize: 26))),
      ),
      childCount: emoji.length,
    ),
  );

  Widget _header(String text, {Key? key}) => SliverToBoxAdapter(
    key: key,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: GlowColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final recent = _repo.recentEmoji;
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              if (recent.isNotEmpty) ...[_header('Recent'), _grid(recent)],
              for (var i = 0; i < emojiCategories.length; i++) ...[
                _header(emojiCategories[i].$2, key: _keys[i]),
                _grid(emojiCategories[i].$3),
              ],
            ],
          ),
        ),
        // Category rail.
        SizedBox(
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < emojiCategories.length; i++)
                InkResponse(
                  radius: 18,
                  onTap: () {
                    final c = _keys[i].currentContext;
                    if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 250));
                  },
                  child: Text(emojiCategories[i].$1, style: const TextStyle(fontSize: 18)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StickerTab extends StatefulWidget {
  const _StickerTab({required this.chatId, required this.onSent});

  final int chatId;
  final VoidCallback onSent;

  @override
  State<_StickerTab> createState() => _StickerTabState();
}

class _StickerTabState extends State<_StickerTab> {
  late final _repo = context.read<MediaPanelRepository>();
  List<td.StickerSetInfo> _sets = const [];
  int? _setId; // null: recent
  Future<List<td.Sticker>>? _stickers;

  @override
  void initState() {
    super.initState();
    _repo.installedSets().then((s) {
      if (!mounted) return;
      setState(() => _sets = s);
    }).ignore();
    _select(null);
  }

  void _select(int? setId) => setState(() {
    _setId = setId;
    _stickers = (setId == null ? _repo.recentStickers() : _repo.setStickers(setId)).then((list) async {
      // Nothing recent yet: show the first pack instead.
      if (list.isEmpty && setId == null) {
        final sets = await _repo.installedSets();
        if (sets.isNotEmpty) {
          if (mounted) setState(() => _setId = sets.first.id);
          return _repo.setStickers(sets.first.id);
        }
      }
      return list;
    });
  });

  Future<void> _send(td.Sticker s) async {
    await _repo.sendSticker(widget.chatId, s);
    widget.onSent();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            _RailButton(
              selected: _setId == null,
              onTap: () => _select(null),
              child: const Icon(Icons.history_rounded, color: GlowColors.textMuted),
            ),
            for (final set in _sets)
              _RailButton(
                selected: _setId == set.id,
                onTap: () => _select(set.id),
                child: set.covers.isNotEmpty
                    ? AnimatedSticker(sticker: set.covers.first, size: 30)
                    : set.thumbnail != null
                    ? TdFileImage(file: set.thumbnail!.file, fit: BoxFit.contain)
                    : Text(set.title.characters.first),
              ),
          ],
        ),
      ),
      Expanded(
        child: FutureBuilder<List<td.Sticker>>(
          future: _stickers,
          builder: (context, snap) {
            final list = snap.data;
            if (list == null) {
              return const Center(child: CircularProgressIndicator(color: GlowColors.violet));
            }
            if (list.isEmpty) {
              return const Center(
                child: Text('No stickers yet', style: TextStyle(color: GlowColors.textMuted)),
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.all(6),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 84),
              itemCount: list.length,
              itemBuilder: (context, i) => Semantics(
                button: true,
                label: '${list[i].emoji} sticker',
                excludeSemantics: true,
                child: InkResponse(
                  onTap: () => _send(list[i]),
                  // Plays once as it appears, then rests (no endless frames).
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: AnimatedSticker(sticker: list[i], size: 72),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.selected, required this.onTap, required this.child});

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Container(
      width: 44,
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: selected ? GlowColors.violet.withValues(alpha: 0.2) : null,
      ),
      child: SizedBox.square(dimension: 30, child: Center(child: child)),
    ),
  );
}

class _GifTab extends StatefulWidget {
  const _GifTab({required this.chatId, required this.onSent});

  final int chatId;
  final VoidCallback onSent;

  @override
  State<_GifTab> createState() => _GifTabState();
}

class _GifTabState extends State<_GifTab> {
  late final _repo = context.read<MediaPanelRepository>();
  late Future<List<td.Animation>> _saved = _repo.savedGifs();
  Future<td.InlineQueryResults>? _search;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() => _search = q.trim().isEmpty ? null : _repo.searchGifs(widget.chatId, q.trim()));
    });
  }

  Future<void> _sent(Future<void> send) async {
    await send;
    widget.onSent();
  }

  // GIFs loop silently in the grid, like Telegram.
  Widget _cell(td.Animation gif, VoidCallback onTap) => Semantics(
    button: true,
    label: 'GIF',
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: LoopingGif(
          file: gif.animation,
          thumbnail: gif.thumbnail?.file,
          minithumbnail: gif.minithumbnail,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: TextField(
          onChanged: _onQuery,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search GIFs',
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: GlowColors.surfaceHigh,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          ),
        ),
      ),
      Expanded(
        child: _search != null
            ? FutureBuilder<td.InlineQueryResults>(
                future: _search,
                builder: (context, snap) {
                  final r = snap.data;
                  if (r == null) {
                    return const Center(child: CircularProgressIndicator(color: GlowColors.violet));
                  }
                  final gifs = r.results.whereType<td.InlineQueryResultAnimation>().toList();
                  return _grid(
                    gifs.length,
                    (i) => _cell(
                      gifs[i].animation,
                      () => _sent(_repo.sendInlineResult(widget.chatId, r.inlineQueryId, gifs[i].id)),
                    ),
                  );
                },
              )
            : FutureBuilder<List<td.Animation>>(
                future: _saved,
                builder: (context, snap) {
                  final list = snap.data;
                  if (list == null) {
                    return const Center(child: CircularProgressIndicator(color: GlowColors.violet));
                  }
                  if (list.isEmpty) {
                    return const Center(
                      child: Text('Search for a GIF above', style: TextStyle(color: GlowColors.textMuted)),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => setState(() => _saved = _repo.savedGifs()),
                    child: _grid(
                      list.length,
                      (i) => _cell(list[i], () => _sent(_repo.sendGif(widget.chatId, list[i]))),
                    ),
                  );
                },
              ),
      ),
    ],
  );

  Widget _grid(int count, Widget Function(int) cell) => GridView.builder(
    padding: const EdgeInsets.all(6),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 130,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
    ),
    itemCount: count,
    itemBuilder: (context, i) => cell(i),
  );
}
