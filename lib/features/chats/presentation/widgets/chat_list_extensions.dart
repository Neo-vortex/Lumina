import 'package:flutter/material.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:provider/provider.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../domain/lens_entry.dart';

/// An action on a lens (folder) from the picker's long-press menu.
class LensAction {
  const LensAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final void Function(BuildContext context) onSelected;
  final bool destructive;
}

/// A folder Telegram suggests, offered when the user has none.
class LensSuggestion {
  const LensSuggestion({required this.title, required this.description, required this.onAdd});

  final String title;
  final String description;
  final Future<void> Function() onAdd;
}

/// An extra entry in a chat row's long-press sheet.
class ChatAction {
  const ChatAction({required this.label, required this.icon, required this.run});

  final String label;
  final IconData icon;

  /// Runs after the actions sheet closed, with the chat list's context.
  final Future<void> Function(BuildContext context) run;
}

/// Lets other features add to the chat list (the proxy button, folders)
/// without the chat list depending on them. Provided by the composition
/// root; the defaults are a plain list with no folders.
class ChatListExtensions {
  const ChatListExtensions();

  static ChatListExtensions of(BuildContext context) {
    try {
      return context.read<ChatListExtensions>();
    } on ProviderNotFoundException {
      return const ChatListExtensions();
    }
  }

  /// Shown before the search button.
  List<Widget> headerActions(BuildContext context) => const [];

  /// Rebuilds the lens when it fires (new chats in shared folders).
  Listenable? get lensListenable => null;

  Color lensColor(LensEntry entry) => entry.isArchive ? GlowColors.archive : GlowColors.violet;

  IconData lensIcon(LensEntry entry) => entry.isArchive
      ? Icons.inventory_2_rounded
      : entry.isMain
      ? Icons.forum_rounded
      : Icons.folder_rounded;

  /// Chats the owner of a joined shared folder added since we last looked.
  int newChatsIn(LensEntry entry) => 0;

  void openNewChats(BuildContext context, LensEntry entry) {}

  List<LensAction> lensActions(BuildContext context, LensEntry entry) => const [];

  VoidCallback? newFolder(BuildContext context) => null;

  VoidCallback? manageFolders(BuildContext context) => null;

  VoidCallback? editFolder(BuildContext context, LensEntry entry) => null;

  Future<List<LensSuggestion>> suggestions() async => const [];

  /// The lens picker opened (time to look for new shared-folder chats).
  void onLensOpened() {}

  List<ChatAction> chatActions(td.Chat chat) => const [];

  /// Small tags after a chat's title (Premium folder tags).
  List<Widget> folderTags(BuildContext context, td.Chat chat) => const [];
}
