import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/widgets/animated_sticker.dart';
import '../../../core/telegram/widgets/gif_preview.dart';
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

  /// How far the panel is expanded above its keyboard height right now
  /// (0 when collapsed). The chat leaves its layout alone for this part:
  /// the expansion covers the messages instead of re-laying them out on
  /// every frame (that relayout made expanding flicker and stutter).
  static double expandedBy = 0;

  @override
  State<MediaPanel> createState() => _MediaPanelState();
}

class _MediaPanelState extends State<MediaPanel> with SingleTickerProviderStateMixin {
  var _tab = 0;
  static const _tabs = ['Emoji', 'Stickers', 'GIFs'];

  /// 0 = keyboard height, 1 = expanded (most of the screen). Dragging the
  /// handle moves it; scrolling the content up expands it first, pulling
  /// down at the top collapses it, like Telegram.
  late final _open = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));

  @override
  void dispose() {
    _open.dispose();
    _pull.dispose();
    MediaPanel.expandedBy = 0;
    super.dispose();
  }

  double get _extra {
    final max = MediaQuery.sizeOf(context).height * 0.75 - MediaQuery.paddingOf(context).top;
    return (max - widget.height).clamp(0.0, double.infinity);
  }

  /// Dragged down below its collapsed height: past [_dismissAt] (or flung)
  /// the panel closes.
  final _pull = ValueNotifier<double>(0);
  static const _dismissAt = 90.0;

  /// Pulled down past the top of the content while collapsed.
  var _overPull = 0.0;

  void _close() {
    _pull.value = 0;
    // The composer's "done" callback hides the panel.
    widget.onSent();
  }

  void _drag(DragUpdateDetails d) {
    final dy = d.delta.dy;
    // Collapsed and going down (or already pulled): the panel follows the
    // finger towards closing.
    if (_open.value == 0 && (dy > 0 || _pull.value > 0)) {
      _pull.value = (_pull.value + dy).clamp(0.0, widget.height);
      return;
    }
    final extra = _extra;
    if (extra <= 0) return;
    _open.value = (_open.value - dy / extra).clamp(0.0, 1.0);
  }

  void _settle(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dy;
    if (_pull.value > 0) {
      if (_pull.value > _dismissAt || v > 700) {
        _close();
      } else {
        _pull.value = 0;
      }
      return;
    }
    final open = v.abs() > 400 ? v < 0 : _open.value > 0.5;
    _open.animateTo(open ? 1 : 0, curve: Curves.easeOutCubic);
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical || n.depth != 0) return false;
    // Scrolling the content up while collapsed: expand first.
    if (n is ScrollUpdateNotification && n.dragDetails != null && (n.scrollDelta ?? 0) > 2 && _open.value < 1) {
      if (!_open.isAnimating) _open.animateTo(1, curve: Curves.easeOutCubic);
    }
    // Pulled down past the top while expanded: collapse; collapsed: a long
    // pull closes the panel.
    if (n is OverscrollNotification && n.dragDetails != null && n.overscroll < -2) {
      if (_open.value > 0) {
        if (!_open.isAnimating) _open.animateTo(0, curve: Curves.easeOutCubic);
      } else if (!_open.isAnimating) {
        _overPull -= n.overscroll;
        if (_overPull > _dismissAt * 1.4) {
          _overPull = 0;
          _close();
        }
      }
    }
    if (n is ScrollEndNotification) _overPull = 0;
    return false;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_open, _pull]),
    builder: (context, child) {
      MediaPanel.expandedBy = _extra * _open.value;
      return Transform.translate(
        offset: Offset(0, _pull.value),
        child: Container(
          width: double.infinity,
          height: widget.height + MediaPanel.expandedBy,
          decoration: BoxDecoration(
            color: GlowColors.surface,
            border: Border(top: BorderSide(color: GlowColors.violet.withValues(alpha: 0.35))),
          ),
          child: child,
        ),
      );
    },
    child: Column(
      children: [
        // The handle and the tab row both drag the panel open or closed.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: _drag,
          onVerticalDragEnd: _settle,
          child: Column(
            children: [
              Semantics(
                button: true,
                label: 'Expand or collapse the panel',
                onTap: () => _open.animateTo(_open.value > 0.5 ? 0 : 1, curve: Curves.easeOutCubic),
                child: Container(
                  margin: const EdgeInsets.only(top: 6),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: GlowColors.outlineStrong, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                child: Row(
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _TabPill(label: _tabs[i], selected: i == _tab, onTap: () => setState(() => _tab = i)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: IndexedStack(
              index: _tab,
              children: [
                _EmojiTab(onEmoji: widget.onEmoji),
                _tab == 1 ? _StickerTab(chatId: widget.chatId, onSent: widget.onSent) : const SizedBox.shrink(),
                _tab == 2 ? _GifTab(chatId: widget.chatId, onSent: widget.onSent) : const SizedBox.shrink(),
              ],
            ),
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
        style: TextStyle(color: selected ? GlowColors.violet : GlowColors.textMuted, fontWeight: FontWeight.w600),
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

  final _query = TextEditingController();
  Timer? _debounce;
  List<String>? _results; // null: not searching
  var _searchSeq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    final text = q.trim();
    if (text.isEmpty) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      final seq = ++_searchSeq;
      final lang = Localizations.maybeLocaleOf(context)?.languageCode;
      final langs = {'en', ?lang}.toList();
      List<String> found;
      try {
        found = await _repo.searchEmoji(text, languages: langs);
      } catch (_) {
        found = const [];
      }
      // Only the latest query lands.
      if (mounted && seq == _searchSeq && _query.text.trim().isNotEmpty) setState(() => _results = found);
    });
  }

  @override
  Widget build(BuildContext context) {
    final recent = _repo.recentEmoji;
    final results = _results;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: TextField(
            controller: _query,
            onChanged: _onQuery,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search emoji',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _query.clear();
                        _onQuery('');
                      },
                    ),
              filled: true,
              fillColor: GlowColors.surfaceHigh,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: results != null
              ? (results.isEmpty
                    ? const Center(
                        child: Text('No emoji found', style: TextStyle(color: GlowColors.textMuted)),
                      )
                    : CustomScrollView(slivers: [_grid(results)]))
              : CustomScrollView(
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
                    if (_results != null) {
                      _query.clear();
                      setState(() => _results = null);
                      // Jump once the category list is back.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final c = _keys[i].currentContext;
                        if (c != null) Scrollable.ensureVisible(c);
                      });
                      return;
                    }
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
                    ? AnimatedSticker(sticker: set.covers.first, size: 30, repeat: true)
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
                  // Loops like Telegram's panel (it used to play once and stop).
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: AnimatedSticker(sticker: list[i], size: 72, repeat: true),
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
    _settle?.cancel();
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
        // Software-decoded, like Telegram: every cell loops at once.
        child: GifPreview(
          file: gif.animation,
          thumbnail: gif.thumbnail?.file,
          paused: _scrolling,
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

  // GIFs pause while the grid scrolls (every visible one decodes video),
  // and play again once it settles, like Telegram.
  var _scrolling = false;
  Timer? _settle;

  Widget _grid(int count, Widget Function(int) cell) => NotificationListener<ScrollNotification>(
    onNotification: (n) {
      // Only the grid's own scrolling, and never left on: a start without
      // its end (the panel settling, a refresh overscroll) froze every GIF
      // a few frames in. Quiet for 250 ms counts as settled.
      if (n.depth != 0) return false;
      if (n is ScrollStartNotification || n is ScrollUpdateNotification) {
        if (!_scrolling) setState(() => _scrolling = true);
        _settle?.cancel();
        _settle = Timer(const Duration(milliseconds: 250), () {
          if (mounted && _scrolling) setState(() => _scrolling = false);
        });
      } else if (n is ScrollEndNotification && _scrolling) {
        _settle?.cancel();
        setState(() => _scrolling = false);
      }
      return false;
    },
    // A decoder per GIF: past the phone's limit they stall after a few
    // frames, so only so many loop at once and none off screen.
    // 12 of the phone's 16 hardware decoders: every cell of the collapsed
    // panel plays; past that (expanded) they take turns.
    child: GifBudget(
      max: 12,
      child: GridView.builder(
        cacheExtent: 0,
        padding: const EdgeInsets.all(6),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: count,
        itemBuilder: (context, i) => cell(i),
      ),
    ),
  );
}
