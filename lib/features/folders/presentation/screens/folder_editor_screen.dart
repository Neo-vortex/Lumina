import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_background.dart';
import '../../../../core/widgets/glow_sheet.dart';
import '../../bloc/folder_editor_cubit.dart';
import '../../data/folders_repository.dart';
import '../../domain/folder_draft.dart';
import '../folder_palette.dart';
import '../widgets/folder_share_sheet.dart';
import 'chat_picker_screen.dart';

/// Create or edit a folder: name, icon, glow colour, rules, chats.
class FolderEditorScreen extends StatefulWidget {
  const FolderEditorScreen({super.key});

  static Route<void> route({int? folderId, FolderDraft? initial}) => MaterialPageRoute(
    builder: (context) => BlocProvider(
      create: (context) => FolderEditorCubit(
        repository: context.read<FoldersRepository>(),
        cache: context.read<TelegramCache>(),
        folderId: folderId,
        initial: initial,
      )..load(),
      child: const FolderEditorScreen(),
    ),
  );

  @override
  State<FolderEditorScreen> createState() => _FolderEditorScreenState();
}

class _FolderEditorScreenState extends State<FolderEditorScreen> {
  final _name = TextEditingController();

  /// Set once the user confirmed discarding changes, so the pop goes through.
  var _leaving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickIcon(FolderEditorCubit cubit) async {
    final picked = await showGlowSheet<String>(
      context,
      title: 'Icon',
      accent: FolderPalette.colorOf(cubit.state.draft.colorId, position: 0),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            IconButton.filledTonal(
              tooltip: 'Automatic',
              onPressed: () => Navigator.pop(context, ''),
              icon: const Icon(Icons.auto_awesome_rounded),
            ),
            for (final e in FolderPalette.iconNames.entries)
              IconButton(
                tooltip: e.key,
                isSelected: cubit.state.draft.iconName == e.key,
                onPressed: () => Navigator.pop(context, e.key),
                icon: Icon(e.value),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    cubit.update((d) => d.copyWith(iconName: () => picked.isEmpty ? null : picked));
  }

  Future<void> _pickChats(FolderEditorCubit cubit, {required bool included}) async {
    final d = cubit.state.draft;
    final result = await ChatPickerScreen.pick(
      context,
      initial: included ? d.included : d.excluded,
      title: included ? 'Include chats' : 'Exclude chats',
    );
    if (result == null) return;
    cubit.update((d) => included ? d.copyWith(included: result) : d.copyWith(excluded: result));
  }

  Future<bool> _confirmDiscard() => showGlowConfirm(
    context,
    title: 'Discard your changes?',
    message: 'The folder stays as it was.',
    confirmLabel: 'Discard',
    icon: Icons.undo_rounded,
    destructive: true,
  );

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    return BlocConsumer<FolderEditorCubit, FolderEditorState>(
      listener: (context, s) {
        if (!s.loading && _name.text.isEmpty && s.draft.name.isNotEmpty) _name.text = s.draft.name;
        if (s.done || (s.deleted && s.error != null)) {
          if (s.deleted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.error!)));
          Navigator.of(context).pop();
        }
      },
      builder: (context, s) {
        final cubit = context.read<FolderEditorCubit>();
        final d = s.draft;
        final color = FolderPalette.colorOf(d.colorId, position: 0);
        Widget chatTile(int id, {required bool included}) {
          final chat = cache.chats[id];
          return ListTile(
            leading: chat == null ? const Icon(Icons.chat_rounded) : ChatAvatar.chat(chat, size: 36),
            title: Text(chat?.title ?? 'Chat', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => cubit.update(
                (d) => included
                    ? d.copyWith(included: d.included.where((x) => x != id).toList())
                    : d.copyWith(excluded: d.excluded.where((x) => x != id).toList()),
              ),
            ),
          );
        }

        FilterChip chip(String label, bool value, FolderDraft Function(FolderDraft, bool) set) => FilterChip(
          label: Text(label),
          selected: value,
          onSelected: (v) => cubit.update((d) => set(d, v)),
        );

        return PopScope(
          canPop: !s.changed || s.done || _leaving,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (await _confirmDiscard() && context.mounted) {
              // PopScope reads canPop on rebuild, so pop after the frame.
              setState(() => _leaving = true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) Navigator.of(context).pop();
              });
            }
          },
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: GlowColors.background,
              title: Text(cubit.folderId == null ? 'New folder' : 'Edit folder'),
              actions: [
                IconButton(
                  tooltip: 'Save',
                  onPressed: s.saving || s.loading ? null : cubit.save,
                  icon: s.saving
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded),
                ),
              ],
            ),
            body: GlowBackground(
              child: s.loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
                      children: [
                        // Ribbon preview in the chosen colour.
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: 6,
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.2)]),
                            boxShadow: glow(color, intensity: 0.6),
                          ),
                        ),
                        TextField(
                          controller: _name,
                          maxLength: FolderDraft.maxNameLength,
                          decoration: const InputDecoration(labelText: 'Folder name'),
                          onChanged: (v) => cubit.update((d) => d.copyWith(name: v)),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Icon'),
                          trailing: Icon(FolderPalette.iconOf(d.iconName), color: color),
                          onTap: () => _pickIcon(cubit),
                        ),
                        const SizedBox(height: 8),
                        const Text('Glow', style: TextStyle(color: GlowColors.textMuted)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('None'),
                              selected: d.colorId < 0,
                              onSelected: (_) => cubit.update((d) => d.copyWith(colorId: -1)),
                            ),
                            for (final c in FolderPalette.choices)
                              ChoiceChip(
                                avatar: CircleAvatar(backgroundColor: c.color, radius: 6),
                                label: Text(c.label),
                                selected: d.colorId == c.colorId,
                                onSelected: (_) => cubit.update((d) => d.copyWith(colorId: c.colorId)),
                              ),
                          ],
                        ),
                        if (!context.read<FoldersRepository>().isPremium)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              'Saved on this device. Telegram Premium syncs folder colours.',
                              style: TextStyle(color: GlowColors.textMuted, fontSize: 12),
                            ),
                          ),
                        const _Header('Included chats'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            chip('Contacts', d.includeContacts, (d, v) => d.copyWith(includeContacts: v)),
                            chip(
                              'Non-contacts',
                              d.includeNonContacts,
                              (d, v) => d.copyWith(includeNonContacts: v),
                            ),
                            chip('Groups', d.includeGroups, (d, v) => d.copyWith(includeGroups: v)),
                            chip('Channels', d.includeChannels, (d, v) => d.copyWith(includeChannels: v)),
                            chip('Bots', d.includeBots, (d, v) => d.copyWith(includeBots: v)),
                          ],
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.add_rounded, color: GlowColors.cyan),
                          title: const Text('Add chats'),
                          onTap: () => _pickChats(cubit, included: true),
                        ),
                        for (final id in d.included) chatTile(id, included: true),
                        const _Header('Excluded chats'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            chip('Muted', d.excludeMuted, (d, v) => d.copyWith(excludeMuted: v)),
                            chip('Read', d.excludeRead, (d, v) => d.copyWith(excludeRead: v)),
                            chip('Archived', d.excludeArchived, (d, v) => d.copyWith(excludeArchived: v)),
                          ],
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.remove_rounded, color: GlowColors.coral),
                          title: const Text('Exclude chats'),
                          onTap: () => _pickChats(cubit, included: false),
                        ),
                        for (final id in d.excluded) chatTile(id, included: false),
                        if (cubit.folderId != null) ...[
                          const _Header('Invite links'),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.share_rounded, color: color),
                            title: const Text('Share this folder'),
                            subtitle: const Text('Others can add it and join its chats with one link'),
                            onTap: () => showFolderShareSheet(
                              context,
                              folderId: cubit.folderId!,
                              title: d.name,
                              color: color,
                            ),
                          ),
                        ],
                        if (s.error != null && !s.deleted)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(s.error!, style: const TextStyle(color: GlowColors.error)),
                          ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: GlowColors.violet,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    ),
  );
}
