import 'package:flutter/material.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';
import '../../../../core/widgets/glow_sheet.dart';
import '../../domain/lens_entry.dart';
import 'chat_list_extensions.dart';

/// The lens panel that drops from the header: every lens with its unread
/// glow, "+N new" for shared folders, suggestions, New / Edit folders.
/// Returns the picked index, or null.
Future<int?> showLensPicker(BuildContext context, {required List<LensEntry> entries, required int current}) {
  final ext = ChatListExtensions.of(context);
  final animate = Motion.ambientEnabled(context);
  return showGeneralDialog<int>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close folders',
    barrierColor: Colors.black54,
    transitionDuration: Motion.standard,
    transitionBuilder: (context, a, _, child) {
      final curved = CurvedAnimation(parent: a, curve: Motion.enter, reverseCurve: Motion.exit);
      final faded = FadeTransition(opacity: curved, child: child);
      if (!animate) return faded;
      return SlideTransition(
        position: Tween(begin: const Offset(0, -0.08), end: Offset.zero).animate(curved),
        child: faded,
      );
    },
    pageBuilder: (dialogContext, _, _) => SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 56, 12, 12),
          child: _Panel(entries: entries, current: current, ext: ext, outer: context),
        ),
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.entries, required this.current, required this.ext, required this.outer});

  final List<LensEntry> entries;
  final int current;
  final ChatListExtensions ext;
  final BuildContext outer;

  @override
  Widget build(BuildContext context) {
    final hasFolders = entries.any((e) => e.folderId != null);
    final newFolder = ext.newFolder(outer);
    final manage = ext.manageFolders(outer);
    final listenable = ext.lensListenable;
    Widget rows() => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < entries.length; i++)
          _LensRow(entry: entries[i], selected: i == current, ext: ext, outer: outer, index: i),
      ],
    );
    return Material(
      color: GlowColors.surfaceHigh,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (listenable == null)
                rows()
              else
                ListenableBuilder(listenable: listenable, builder: (_, _) => rows()),
              if (!hasFolders) _Suggestions(ext: ext),
              if (newFolder != null || manage != null) const Divider(height: 16, color: GlowColors.outline),
              if (newFolder != null)
                ListTile(
                  leading: const Icon(Icons.add_rounded, color: GlowColors.cyan),
                  title: const Text('New folder'),
                  onTap: () {
                    Navigator.of(context).pop();
                    newFolder();
                  },
                ),
              if (manage != null)
                ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('Edit folders'),
                  onTap: () {
                    Navigator.of(context).pop();
                    manage();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LensRow extends StatelessWidget {
  const _LensRow({
    required this.entry,
    required this.selected,
    required this.ext,
    required this.outer,
    required this.index,
  });

  final LensEntry entry;
  final bool selected;
  final ChatListExtensions ext;
  final BuildContext outer;
  final int index;

  Future<void> _actions(BuildContext context) async {
    final actions = ext.lensActions(outer, entry);
    if (actions.isEmpty) return;
    final picked = await showGlowSheet<LensAction>(
      context,
      title: entry.title,
      accent: ext.lensColor(entry),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in actions)
              ListTile(
                leading: Icon(a.icon, color: a.destructive ? GlowColors.coral : null),
                title: Text(a.label, style: a.destructive ? const TextStyle(color: GlowColors.coral) : null),
                onTap: () => Navigator.of(context).pop(a),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    Navigator.of(context).pop();
    picked.onSelected(outer);
  }

  @override
  Widget build(BuildContext context) {
    final color = ext.lensColor(entry);
    final fresh = ext.newChatsIn(entry);
    final unread = entry.unread;
    return Material(
      color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(index),
        onLongPress: () => _actions(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.18),
                  boxShadow: selected ? glow(color, intensity: 0.6) : null,
                ),
                child: Icon(ext.lensIcon(entry), size: 18, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
              if (fresh > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ActionChip(
                    label: Text('+$fresh new'),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: color),
                    onPressed: () {
                      Navigator.of(context).pop();
                      ext.openNewChats(outer, entry);
                    },
                  ),
                ),
              if (unread.chats > 0)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  constraints: const BoxConstraints(minWidth: 22),
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: unread.unmuted > 0 ? GlowColors.teal : GlowColors.surface,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    unread.chats > 999 ? '999+' : '${unread.chats}',
                    style: TextStyle(
                      color: unread.unmuted > 0 ? GlowColors.onAccent : GlowColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Telegram's suggested folders as one-tap chips (only when there are no
/// folders yet).
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.ext});

  final ChatListExtensions ext;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LensSuggestion>>(
      future: ext.suggestions(),
      builder: (context, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in items)
                Tooltip(
                  message: s.description,
                  child: ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 16),
                    label: Text(s.title),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await s.onAdd();
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
