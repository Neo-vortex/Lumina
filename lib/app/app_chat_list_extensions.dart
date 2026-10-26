import 'package:flutter/material.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../core/telegram/telegram_cache.dart';
import '../core/theme/glow_colors.dart';
import '../core/widgets/glow_sheet.dart';
import '../features/chats/domain/lens_entry.dart';
import '../features/chats/presentation/widgets/chat_list_extensions.dart';
import '../features/folders/data/folders_repository.dart';
import '../features/folders/presentation/folder_palette.dart';
import '../features/folders/presentation/screens/folder_editor_screen.dart';
import '../features/folders/presentation/screens/folder_manager_screen.dart';
import '../features/folders/presentation/widgets/add_to_folder_sheet.dart';
import '../features/folders/presentation/widgets/folder_share_sheet.dart';
import '../features/folders/presentation/widgets/join_folder_sheet.dart';
import '../features/proxy/presentation/widgets/proxy_button.dart';

/// Folders and the proxy button, plugged into the chat list.
class AppChatListExtensions extends ChatListExtensions {
  AppChatListExtensions({required this.folders, required this.cache});

  final FoldersRepository folders;
  final TelegramCache cache;

  @override
  List<Widget> headerActions(BuildContext context) => const [ProxyButton()];

  @override
  Listenable? get lensListenable => folders.newChats;

  int _position(int folderId) => cache.chatFolders.indexWhere((f) => f.id == folderId);

  Color _folderColor(td.ChatFolderInfo f) =>
      FolderPalette.colorOf(folders.colorIdOf(f), position: _position(f.id));

  @override
  Color lensColor(LensEntry entry) {
    final f = entry.folder;
    if (f != null) return _folderColor(f);
    return entry.isArchive ? GlowColors.archive : GlowColors.violet;
  }

  @override
  IconData lensIcon(LensEntry entry) {
    final f = entry.folder;
    return f == null ? super.lensIcon(entry) : FolderPalette.iconOf(f.icon.name);
  }

  @override
  int newChatsIn(LensEntry entry) => folders.newChats.value[entry.folderId]?.length ?? 0;

  @override
  void openNewChats(BuildContext context, LensEntry entry) {
    final ids = folders.newChats.value[entry.folderId];
    if (ids != null) showJoinFolderSheet(context, folderId: entry.folderId, chatIds: ids);
  }

  @override
  List<LensAction> lensActions(BuildContext context, LensEntry entry) {
    final readAll = LensAction(
      label: 'Mark all as read',
      icon: Icons.mark_chat_read_rounded,
      onSelected: (context) => folders.readAll(entry.list).ignore(),
    );
    final f = entry.folder;
    if (f == null) return [readAll];
    final anyUnmuted = cache.chatsIn(entry.list).any((c) => !cache.isMuted(c));
    return [
      LensAction(
        label: 'Edit',
        icon: Icons.edit_rounded,
        onSelected: (context) => Navigator.of(context).push(FolderEditorScreen.route(folderId: f.id)),
      ),
      LensAction(
        label: 'Share',
        icon: Icons.share_rounded,
        onSelected: (context) =>
            showFolderShareSheet(context, folderId: f.id, title: f.name.text.text, color: _folderColor(f)),
      ),
      readAll,
      LensAction(
        label: anyUnmuted ? 'Mute all' : 'Unmute all',
        icon: anyUnmuted ? Icons.notifications_off_rounded : Icons.notifications_rounded,
        onSelected: (context) => folders.setAllMuted(entry.list, muted: anyUnmuted).ignore(),
      ),
      LensAction(
        label: 'Delete',
        icon: Icons.delete_outline_rounded,
        destructive: true,
        onSelected: (context) async {
          final ok = await showGlowConfirm(
            context,
            title: 'Delete “${f.name.text.text}”?',
            message: 'Its chats stay in All chats.',
            confirmLabel: 'Delete folder',
            icon: Icons.folder_delete_rounded,
            destructive: true,
          );
          if (ok) await folders.delete(f.id);
        },
      ),
    ];
  }

  @override
  VoidCallback? newFolder(BuildContext context) =>
      () => Navigator.of(context).push(FolderEditorScreen.route());

  @override
  VoidCallback? manageFolders(BuildContext context) =>
      () => Navigator.of(context).push(FolderManagerScreen.route());

  @override
  VoidCallback? editFolder(BuildContext context, LensEntry entry) {
    final id = entry.folderId;
    return id == null ? null : () => Navigator.of(context).push(FolderEditorScreen.route(folderId: id));
  }

  @override
  Future<List<LensSuggestion>> suggestions() async {
    try {
      return [
        for (final r in await folders.recommended())
          LensSuggestion(
            title: r.folder.name.text.text,
            description: r.description,
            onAdd: () => folders.addRecommended(r.folder),
          ),
      ];
    } on Exception {
      return const [];
    }
  }

  @override
  void onLensOpened() => folders.refreshNewChats().ignore();

  @override
  List<ChatAction> chatActions(td.Chat chat) => [
    ChatAction(
      label: 'Add to folder…',
      icon: Icons.create_new_folder_rounded,
      run: (context) => showAddToFolderSheet(context, chat),
    ),
  ];

  @override
  List<Widget> folderTags(BuildContext context, td.Chat chat) {
    if (!cache.folderTagsEnabled) return const [];
    return [
      for (final id in cache.foldersOf(chat).take(2))
        if (cache.chatFolders.where((f) => f.id == id).firstOrNull case final f?)
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: _folderColor(f).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              f.name.text.text,
              style: TextStyle(color: _folderColor(f), fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
    ];
  }
}
