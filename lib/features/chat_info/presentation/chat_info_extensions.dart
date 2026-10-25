import 'package:flutter/material.dart';
import 'package:lumina_tdlib/api.dart' as td;

/// An extra tab on the chat info screen, contributed by another feature
/// (e.g. saved story history). [slivers] fill the page below the header.
class ChatInfoTab {
  const ChatInfoTab({required this.label, required this.icon, required this.slivers});

  final String label;
  final IconData icon;
  final List<Widget> Function(BuildContext context) slivers;
}

/// Provided by the composition root; the default adds nothing.
class ChatInfoExtensions {
  const ChatInfoExtensions();

  List<ChatInfoTab> tabs(BuildContext context, td.Chat chat) => const [];
}
