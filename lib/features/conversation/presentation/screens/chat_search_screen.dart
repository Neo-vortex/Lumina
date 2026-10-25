import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../../core/search/message_search.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../data/messages_repository.dart';

/// Searches one chat. Pops with the chosen message id.
///
/// Uses the local full-text index ([MessageSearch]) when enabled (fast,
/// precise substring matching in any script), falling back to TDLib's
/// search, which also supports media-type filters.
class ChatSearchScreen extends StatefulWidget {
  const ChatSearchScreen({super.key, required this.chat});

  final td.Chat chat;

  static Route<int> route(td.Chat chat) => MaterialPageRoute(builder: (_) => ChatSearchScreen(chat: chat));

  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

enum _Filter { all, photos, videos, files, links, voice }

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  var _filter = _Filter.all;
  var _loading = false;
  List<({td.Message? message, int messageId, String snippet})> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _run);
  }

  td.SearchMessagesFilter? get _tdFilter => switch (_filter) {
    _Filter.all => null,
    _Filter.photos => const td.SearchMessagesFilterPhoto(),
    _Filter.videos => const td.SearchMessagesFilterVideo(),
    _Filter.files => const td.SearchMessagesFilterDocument(),
    _Filter.links => const td.SearchMessagesFilterUrl(),
    _Filter.voice => const td.SearchMessagesFilterVoiceNote(),
  };

  Future<void> _run() async {
    final q = _query.text.trim();
    if (q.isEmpty && _filter == _Filter.all) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _loading = true);
    final repo = context.read<MessagesRepository>();
    try {
      MessageSearch? local;
      try {
        local = context.read<MessageSearch>();
      } on ProviderNotFoundException {
        local = null;
      }
      if (local != null && local.enabled && _filter == _Filter.all && q.isNotEmpty) {
        final hits = await local.search(q, chatId: widget.chat.id);
        if (!mounted || _query.text.trim() != q) return;
        setState(() {
          _results = [for (final h in hits) (message: null, messageId: h.messageId, snippet: h.snippet)];
          _loading = false;
        });
        return;
      }
      final found = await repo.searchInChat(widget.chat.id, q, filter: _tdFilter);
      if (!mounted || _query.text.trim() != q) return;
      final cache = context.read<TelegramCache>();
      setState(() {
        _results = [for (final m in found) (message: m, messageId: m.id, snippet: Display.preview(cache, m))];
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: GlowColors.background,
        title: TextField(
          controller: _query,
          autofocus: true,
          onChanged: (_) => _schedule(),
          decoration: InputDecoration(hintText: 'Search in ${widget.chat.title}', border: InputBorder.none),
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final f in _Filter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(switch (f) {
                        _Filter.all => 'All',
                        _Filter.photos => 'Photos',
                        _Filter.videos => 'Videos',
                        _Filter.files => 'Files',
                        _Filter.links => 'Links',
                        _Filter.voice => 'Voice',
                      }),
                      selected: _filter == f,
                      selectedColor: GlowColors.violetDeep,
                      onSelected: (_) {
                        setState(() => _filter = f);
                        _run();
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2, color: GlowColors.violet),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _query.text.isEmpty ? 'Type to search' : 'No messages found',
                      style: const TextStyle(color: GlowColors.textMuted),
                    ),
                  )
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: GlowColors.outline),
                    itemBuilder: (context, i) {
                      final r = _results[i];
                      final m = r.message;
                      return ListTile(
                        leading: m == null
                            ? const Icon(Icons.chat_bubble_outline_rounded, color: GlowColors.cyan)
                            : switch (m.senderId) {
                                td.MessageSenderUser(:final userId) => ChatAvatar.user(
                                  cache.users[userId],
                                  size: 40,
                                ),
                                td.MessageSenderChat() => ChatAvatar.chat(widget.chat, size: 40),
                              },
                        title: m == null
                            ? null
                            : Text(
                                m.isOutgoing ? 'You' : Display.senderName(cache, m.senderId),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                        subtitle: _Highlighted(text: r.snippet, query: _query.text.trim()),
                        trailing: m == null
                            ? null
                            : Text(
                                Display.listTime(Display.messageDate(m), DateTime.now()),
                                style: const TextStyle(color: GlowColors.textMuted, fontSize: 12),
                              ),
                        onTap: () => Navigator.pop(context, r.messageId),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Highlights occurrences of [query] (case-insensitive), or text wrapped in
/// the index's `[[…]]` markers.
class _Highlighted extends StatelessWidget {
  const _Highlighted({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    const hl = TextStyle(color: GlowColors.amber, fontWeight: FontWeight.w700);
    final spans = <TextSpan>[];
    if (text.contains('[[')) {
      final re = RegExp(r'\[\[(.*?)\]\]');
      var last = 0;
      for (final m in re.allMatches(text)) {
        spans
          ..add(TextSpan(text: text.substring(last, m.start)))
          ..add(TextSpan(text: m.group(1), style: hl));
        last = m.end;
      }
      spans.add(TextSpan(text: text.substring(last)));
    } else if (query.isNotEmpty) {
      final lower = text.toLowerCase(), q = query.toLowerCase();
      var last = 0;
      for (var i = lower.indexOf(q); i >= 0; i = lower.indexOf(q, i + q.length)) {
        spans
          ..add(TextSpan(text: text.substring(last, i)))
          ..add(TextSpan(text: text.substring(i, i + q.length), style: hl));
        last = i + q.length;
      }
      spans.add(TextSpan(text: text.substring(last)));
    } else {
      spans.add(TextSpan(text: text));
    }
    return Text.rich(TextSpan(children: spans), maxLines: 2, overflow: TextOverflow.ellipsis);
  }
}
