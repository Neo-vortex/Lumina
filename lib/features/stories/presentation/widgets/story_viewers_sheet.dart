import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../data/stories_repository.dart';

/// Who viewed, reacted to, forwarded or reposted the user's own (or their
/// channel's, [asChat]) story.
Future<void> showStoryViewers(BuildContext context, td.Story story, {required bool asChat}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: GlowColors.surfaceHigh,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (context, scroll) => _ViewersList(story: story, asChat: asChat, scroll: scroll),
      ),
    );

class _ViewersList extends StatefulWidget {
  const _ViewersList({required this.story, required this.asChat, required this.scroll});

  final td.Story story;
  final bool asChat;
  final ScrollController scroll;

  @override
  State<_ViewersList> createState() => _ViewersListState();
}

class _ViewersListState extends State<_ViewersList> {
  late final StoriesRepository _repo = context.read<StoriesRepository>();
  final _items = <td.StoryInteraction>[];
  td.StoryInteractions? _last;
  var _loading = false;
  var _reactionsFirst = false;
  var _contactsOnly = false;
  var _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    widget.scroll.addListener(() {
      final p = widget.scroll.position;
      if (p.extentAfter < 400) _load();
    });
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (!reset && (_last == null || _last!.nextOffset.isEmpty)) return;
    _loading = true;
    try {
      final r = await _repo.interactions(
        widget.story,
        asChat: widget.asChat,
        query: _query,
        onlyContacts: _contactsOnly,
        reactionsFirst: _reactionsFirst,
        offset: reset ? '' : _last!.nextOffset,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(r.interactions);
        _last = r;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Viewers aren’t available for this story.');
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final info = widget.story.interactionInfo;
    final last = _last;
    final views = last?.totalCount ?? info?.viewCount ?? 0;
    return CustomScrollView(
      controller: widget.scroll,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    '$views views',
                    if ((last?.totalReactionCount ?? info?.reactionCount ?? 0) > 0)
                      '${last?.totalReactionCount ?? info?.reactionCount} reactions',
                    if ((last?.totalForwardCount ?? info?.forwardCount ?? 0) > 0)
                      '${last?.totalForwardCount ?? info?.forwardCount} shares',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                if (widget.story.hasExpiredViewers)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'The full viewer list is kept for 24 hours after a story expires.',
                      style: TextStyle(color: GlowColors.textMuted, fontSize: 13),
                    ),
                  ),
                if (!widget.asChat) ...[
                  const SizedBox(height: 10),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search viewers',
                    ),
                    onChanged: (q) {
                      _query = q.trim();
                      _load(reset: true);
                    },
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Reactions first'),
                        selected: _reactionsFirst,
                        onSelected: (v) {
                          setState(() => _reactionsFirst = v);
                          _load(reset: true);
                        },
                      ),
                      FilterChip(
                        label: const Text('Contacts only'),
                        selected: _contactsOnly,
                        onSelected: (v) {
                          setState(() => _contactsOnly = v);
                          _load(reset: true);
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, style: const TextStyle(color: GlowColors.textMuted)),
            ),
          )
        else if (last != null && _items.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No views yet', style: TextStyle(color: GlowColors.textMuted)),
            ),
          ),
        SliverList.builder(
          itemCount: _items.length,
          itemBuilder: (context, i) {
            final it = _items[i];
            final chat = switch (it.actorId) {
              td.MessageSenderChat(:final chatId) => cache.chats[chatId],
              _ => null,
            };
            final user = switch (it.actorId) {
              td.MessageSenderUser(:final userId) => cache.users[userId],
              _ => null,
            };
            final when = Display.relativeTime(
              DateTime.fromMillisecondsSinceEpoch(it.interactionDate * 1000),
              DateTime.now(),
            );
            final (Widget? trailing, String what) = switch (it.type) {
              td.StoryInteractionTypeView(chosenReactionType: td.ReactionTypeEmoji(:final emoji)) => (
                Text(emoji, style: const TextStyle(fontSize: 22)),
                'Viewed',
              ),
              td.StoryInteractionTypeView() => (null, 'Viewed'),
              td.StoryInteractionTypeForward() => (
                const Icon(Icons.forward_rounded, color: GlowColors.cyan),
                'Shared in a chat',
              ),
              td.StoryInteractionTypeRepost() => (
                const Icon(Icons.repeat_rounded, color: GlowColors.violet),
                'Reposted',
              ),
            };
            return ListTile(
              leading: chat != null ? ChatAvatar.chat(chat, size: 40) : ChatAvatar.user(user, size: 40),
              title: Text(chat?.title ?? Display.userName(user)),
              subtitle: Text(
                '$what · $when${it.blockList is td.BlockListStories ? ' · hidden from your stories' : ''}',
              ),
              trailing: trailing,
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
