import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_sheet.dart';
import '../../data/folders_repository.dart';
import '../../domain/folder_draft.dart';
import '../../domain/folder_errors.dart';
import '../folder_palette.dart';
import '../screens/folder_editor_screen.dart';

/// Chat long-press → "Add to folder…": tick folders in or out.
Future<void> showAddToFolderSheet(BuildContext context, td.Chat chat) => showGlowSheet<void>(
  context,
  title: 'Folders for ${chat.title}',
  builder: (_) => _AddToFolder(chat: chat, outer: context),
);

class _AddToFolder extends StatefulWidget {
  const _AddToFolder({required this.chat, required this.outer});

  final td.Chat chat;
  final BuildContext outer;

  @override
  State<_AddToFolder> createState() => _AddToFolderState();
}

class _AddToFolderState extends State<_AddToFolder> {
  late final FoldersRepository _repo = context.read<FoldersRepository>();
  late final TelegramCache _cache = context.read<TelegramCache>();
  late final Set<int> _in = {..._cache.foldersOf(widget.chat)};
  Set<int>? _addable;
  final _busy = <int>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo
        .foldersToAddChat(widget.chat.id)
        .then(
          (ids) {
            if (mounted) setState(() => _addable = {...ids});
          },
          onError: (_) {
            if (mounted) setState(() => _addable = const {});
          },
        );
  }

  Future<void> _toggle(int folderId, bool add) async {
    setState(() {
      _busy.add(folderId);
      _error = null;
      add ? _in.add(folderId) : _in.remove(folderId);
    });
    try {
      await _repo.setChatInFolder(widget.chat.id, folderId, inFolder: add);
    } catch (e) {
      if (mounted) {
        setState(() {
          add ? _in.remove(folderId) : _in.add(folderId);
          _error = folderErrorText(e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy.remove(folderId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final folders = _cache.chatFolders;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_addable == null) const LinearProgressIndicator(minHeight: 2),
        for (var i = 0; i < folders.length; i++)
          Builder(
            builder: (context) {
              final f = folders[i];
              final inside = _in.contains(f.id);
              final enabled = !_busy.contains(f.id) && (inside || (_addable?.contains(f.id) ?? false));
              final color = FolderPalette.colorOf(_repo.colorIdOf(f), position: i);
              return CheckboxListTile(
                value: inside,
                activeColor: color,
                onChanged: enabled ? (v) => _toggle(f.id, v!) : null,
                secondary: Icon(FolderPalette.iconOf(f.icon.name), color: color),
                title: Text(f.name.text.text),
              );
            },
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(_error!, style: const TextStyle(color: GlowColors.error)),
          ),
        ListTile(
          leading: const Icon(Icons.create_new_folder_rounded, color: GlowColors.cyan),
          title: const Text('New folder with this chat'),
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(widget.outer).push(
              FolderEditorScreen.route(
                initial: const FolderDraft.empty().copyWith(included: [widget.chat.id]),
              ),
            );
          },
        ),
      ],
    );
  }
}
