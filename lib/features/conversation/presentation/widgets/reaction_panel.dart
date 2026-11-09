import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/glow_colors.dart';

/// Where the full reaction panel gets its sections, categories and search
/// results. Everything it returns is filtered to the chat's reactions.
abstract class ReactionCatalog {
  /// Your recently used and the popular reactions, as TDLib orders them.
  Future<({List<String> recent, List<String> popular})> sections();

  /// Named emoji groups (Love, Approval, Laughter…).
  Future<List<({String name, List<String> emojis})>> categories();

  /// Emoji whose keywords match [query].
  Future<List<String>> search(String query);
}

/// The expanded reaction picker, like Telegram's: a search box, a row of
/// categories, and a grid of the chat's reactions in sections (Recent,
/// Popular, then everything else). Searching or picking a category narrows
/// the grid; only reactions this chat accepts are ever shown.
class ReactionPanel extends StatefulWidget {
  const ReactionPanel({
    super.key,
    required this.available,
    required this.onPick,
    required this.icon,
    this.catalog,
    this.height = 360,
  });

  /// Every reaction the chat allows (the chat's own spelling of each).
  final List<String> available;
  final ValueChanged<String> onPick;
  final Widget Function(String emoji, double size) icon;
  final ReactionCatalog? catalog;
  final double height;

  @override
  State<ReactionPanel> createState() => _ReactionPanelState();
}

/// Emoji compared without the variation selector: the chat's heart is a
/// plain ❤ while keyword search gives ❤️.
String _plain(String e) => e.replaceAll('️', '');

class _ReactionPanelState extends State<ReactionPanel> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<String> _recent = const [];
  List<String> _popular = const [];
  List<({String name, List<String> emojis})> _categories = const [];

  /// null: all sections; otherwise the picked category's index.
  int? _category;
  List<String>? _results;
  var _searching = false;

  late final Map<String, String> _byPlain = {for (final e in widget.available) _plain(e): e};

  @override
  void initState() {
    super.initState();
    final catalog = widget.catalog;
    if (catalog == null) return;
    catalog
        .sections()
        .then((s) {
          if (!mounted) return;
          setState(() {
            _recent = _only(s.recent);
            _popular = _only(s.popular);
          });
        })
        .catchError((Object _) {});
    catalog
        .categories()
        .then((c) {
          if (!mounted) return;
          setState(
            () => _categories = [
              for (final g in c)
                if (_only(g.emojis) case final emojis when emojis.isNotEmpty) (name: g.name, emojis: emojis),
            ],
          );
        })
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// [list] narrowed to the chat's reactions, in the chat's spelling, once each.
  List<String> _only(Iterable<String> list) {
    final seen = <String>{};
    return [
      for (final e in list)
        if (_byPlain[_plain(e)] case final r? when seen.add(r)) r,
    ];
  }

  void _search(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.isEmpty) {
      setState(() {
        _results = null;
        _searching = false;
      });
      return;
    }
    // A pasted emoji finds itself.
    final direct = _only([q]);
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      var found = <String>[];
      try {
        found = await widget.catalog?.search(q) ?? const [];
      } catch (_) {}
      if (!mounted || _query.text.trim() != q) return;
      setState(() {
        _results = _only([...direct, ...found]);
        _searching = false;
      });
    });
  }

  Widget _grid(List<String> emojis) => SliverGrid(
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 56, mainAxisExtent: 56),
    delegate: SliverChildBuilderDelegate(
      (context, i) => _Cell(emoji: emojis[i], icon: widget.icon(emojis[i], 42), onTap: widget.onPick),
      childCount: emojis.length,
    ),
  );

  Widget _header(String text) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
      child: Text(
        text,
        style: const TextStyle(color: GlowColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    ),
  );

  List<Widget> _body() {
    if (_results case final results?) {
      if (results.isEmpty && !_searching) {
        return [
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text('No reactions match', style: TextStyle(color: GlowColors.textMuted)),
            ),
          ),
        ];
      }
      return [_header('RESULTS'), _grid(results)];
    }
    if (_category case final i? when i < _categories.length) {
      final c = _categories[i];
      return [_header(c.name.toUpperCase()), _grid(c.emojis)];
    }
    final shown = <String>{..._recent, ..._popular};
    final rest = [
      for (final e in widget.available)
        if (!shown.contains(e)) e,
    ];
    return [
      if (_recent.isNotEmpty) ...[_header('RECENT'), _grid(_recent)],
      if (_popular.isNotEmpty) ...[_header('POPULAR'), _grid(_popular)],
      if (rest.isNotEmpty) ...[_header(shown.isEmpty ? 'ALL REACTIONS' : 'MORE REACTIONS'), _grid(rest)],
    ];
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: TextField(
            controller: _query,
            onChanged: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search reactions',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _query.clear();
                        _search('');
                      },
                    ),
              filled: true,
              fillColor: GlowColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (_results == null && _categories.isNotEmpty)
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _Chip(
                  label: 'All',
                  selected: _category == null,
                  onTap: () => setState(() => _category = null),
                ),
                for (var i = 0; i < _categories.length; i++)
                  _Chip(
                    label: _categories[i].name,
                    leading: widget.icon(_categories[i].emojis.first, 18),
                    selected: _category == i,
                    onTap: () => setState(() => _category = i),
                  ),
              ],
            ),
          ),
        if (_searching) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: CustomScrollView(
            key: ValueKey('reactions-${_results != null}-$_category'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
                sliver: SliverMainAxisGroup(slivers: _body()),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap, this.leading});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
    child: ChoiceChip(
      avatar: leading,
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      labelStyle: TextStyle(fontSize: 12.5, color: selected ? GlowColors.text : GlowColors.textMuted),
      selectedColor: GlowColors.violet.withValues(alpha: 0.35),
      backgroundColor: GlowColors.surface,
      side: BorderSide(color: selected ? GlowColors.violet : GlowColors.outline),
    ),
  );
}

class _Cell extends StatelessWidget {
  const _Cell({required this.emoji, required this.icon, required this.onTap});

  final String emoji;
  final Widget icon;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'React $emoji',
    excludeSemantics: true,
    child: InkResponse(
      radius: 24,
      onTap: () => onTap(emoji),
      child: Center(child: icon),
    ),
  );
}
