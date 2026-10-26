import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../data/folders_repository.dart';

/// Multi-select chats (folder include/exclude lists).
class ChatPickerScreen extends StatefulWidget {
  const ChatPickerScreen({super.key, required this.initial, required this.title});

  final List<int> initial;
  final String title;

  static Future<List<int>?> pick(
    BuildContext context, {
    required List<int> initial,
    String title = 'Choose chats',
  }) => Navigator.of(context).push<List<int>>(
    MaterialPageRoute(
      builder: (_) => ChatPickerScreen(initial: initial, title: title),
    ),
  );

  @override
  State<ChatPickerScreen> createState() => _ChatPickerScreenState();
}

class _ChatPickerScreenState extends State<ChatPickerScreen> {
  late final Set<int> _selected = {...widget.initial};
  List<int>? _results;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final ids = q.trim().isEmpty ? null : await context.read<FoldersRepository>().searchChats(q);
      if (mounted) setState(() => _results = ids);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final ids =
        _results ??
        [
          ...widget.initial,
          for (final c in cache.chatsIn(const td.ChatListMain()))
            if (!widget.initial.contains(c.id)) c.id,
        ];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: GlowColors.background,
        title: Text('${widget.title} (${_selected.length})'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_selected.toList()),
            child: const Text('Done'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: _search,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search'),
            ),
          ),
        ),
      ),
      body: ListView.builder(
        itemCount: ids.length,
        itemBuilder: (context, i) {
          final chat = cache.chats[ids[i]];
          if (chat == null) return const SizedBox.shrink();
          return CheckboxListTile(
            value: _selected.contains(chat.id),
            onChanged: (v) => setState(() => v! ? _selected.add(chat.id) : _selected.remove(chat.id)),
            secondary: ChatAvatar.chat(chat, size: 40),
            title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          );
        },
      ),
    );
  }
}
