import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_background.dart';
import '../../../../core/widgets/glow_sheet.dart';
import '../../bloc/folder_manager_cubit.dart';
import '../../data/folders_repository.dart';
import '../folder_palette.dart';
import 'folder_editor_screen.dart';

/// Edit folders: reorder (All chats included), delete, suggestions, tags.
class FolderManagerScreen extends StatelessWidget {
  const FolderManagerScreen({super.key});

  static Route<void> route() => MaterialPageRoute(
    builder: (context) => BlocProvider(
      create: (context) => FolderManagerCubit(
        repository: context.read<FoldersRepository>(),
        cache: context.read<TelegramCache>(),
      )..load(),
      child: const FolderManagerScreen(),
    ),
  );

  Future<void> _delete(BuildContext context, td.ChatFolderInfo f) async {
    final cubit = context.read<FolderManagerCubit>();
    final joined = f.isShareable && !f.hasMyInviteLinks;
    var leave = <int>{};
    var candidates = const <int>[];
    if (joined) {
      try {
        candidates = await cubit.chatsToLeave(f.id);
        leave = {...candidates};
      } on Exception {
        candidates = const [];
      }
    }
    if (!context.mounted) return;
    final cache = context.read<TelegramCache>();
    final ok = await showGlowConfirm(
      context,
      title: 'Delete “${f.name.text.text}”?',
      message: candidates.isEmpty ? 'Its chats stay in All chats.' : 'Also leave these chats?',
      confirmLabel: 'Delete folder',
      icon: Icons.folder_delete_rounded,
      destructive: true,
      body: candidates.isEmpty
          ? null
          : (context) => StatefulBuilder(
              builder: (context, setState) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final id in candidates)
                    CheckboxListTile(
                      dense: true,
                      value: leave.contains(id),
                      title: Text(cache.chats[id]?.title ?? 'Chat'),
                      onChanged: (v) => setState(() => v! ? leave.add(id) : leave.remove(id)),
                    ),
                ],
              ),
            ),
    );
    if (ok) await cubit.delete(f.id, leave: leave.toList());
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<FoldersRepository>();
    return BlocConsumer<FolderManagerCubit, FolderManagerState>(
      listenWhen: (a, b) => b.error != null && a.error != b.error,
      listener: (context, s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.error!))),
      builder: (context, s) {
        final cubit = context.read<FolderManagerCubit>();
        final cache = context.read<TelegramCache>();
        return Scaffold(
          appBar: AppBar(backgroundColor: GlowColors.background, title: const Text('Folders')),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: GlowColors.violetDeep,
            onPressed: () => Navigator.of(context).push(FolderEditorScreen.route()),
            icon: const Icon(Icons.add_rounded),
            label: const Text('New folder'),
          ),
          body: GlowBackground(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverReorderableList(
                    itemCount: s.rows.length,
                    onReorder: cubit.reorder,
                    itemBuilder: (context, i) {
                      final row = s.rows[i];
                      final f = row.folder;
                      final color = f == null
                          ? GlowColors.violet
                          : FolderPalette.colorOf(
                              repo.colorIdOf(f),
                              position: cache.chatFolders.indexWhere((x) => x.id == f.id),
                            );
                      return Card(
                        key: ValueKey(f?.id ?? 'main'),
                        color: GlowColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(color: color.withValues(alpha: 0.5)),
                        ),
                        child: ListTile(
                          leading: Icon(
                            f == null ? Icons.forum_rounded : FolderPalette.iconOf(f.icon.name),
                            color: color,
                          ),
                          title: Text(f == null ? 'All chats' : f.name.text.text),
                          subtitle: f == null
                              ? null
                              : Text(
                                  f.isShareable
                                      ? (f.hasMyInviteLinks ? 'Shared by you' : 'Shared folder')
                                      : 'Folder',
                                ),
                          onTap: f == null
                              ? null
                              : () => Navigator.of(context).push(FolderEditorScreen.route(folderId: f.id)),
                          onLongPress: f == null ? null : () => _delete(context, f),
                          trailing: ReorderableDragStartListener(
                            index: i,
                            child: const Icon(Icons.drag_handle_rounded, color: GlowColors.textMuted),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Text(
                      'Drag to reorder. Long-press a folder to delete it.',
                      style: TextStyle(color: GlowColors.textMuted, fontSize: 12),
                    ),
                  ),
                ),
                if (s.recommended.isNotEmpty)
                  SliverList.list(
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
                        child: Text(
                          'SUGGESTED',
                          style: TextStyle(
                            color: GlowColors.violet,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      for (final r in s.recommended)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                          leading: Icon(FolderPalette.iconOf(r.folder.icon?.name), color: GlowColors.cyan),
                          title: Text(r.folder.name.text.text),
                          subtitle: Text(r.description),
                          trailing: TextButton(
                            onPressed: () => cubit.addRecommended(r),
                            child: const Text('Add'),
                          ),
                        ),
                    ],
                  ),
                if (cubit.isPremium)
                  SliverToBoxAdapter(
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                      value: s.tagsEnabled,
                      onChanged: cubit.setTags,
                      title: const Text('Folder tags'),
                      subtitle: const Text('Show which folders a chat is in, next to its name'),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        );
      },
    );
  }
}
