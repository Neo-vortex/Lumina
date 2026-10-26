import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/storage/app_preferences.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/luminous_refresh.dart';
import '../../bloc/chat_list_cubit.dart';
import '../../data/chats_repository.dart';
import '../../domain/lens_entry.dart';
import 'chat_actions_sheet.dart';
import 'chat_list_extensions.dart';
import 'timeline_chat_row.dart';

/// One lens page: its own chat list, kept alive while swiping so each page
/// keeps its scroll position.
class ChatListPage extends StatefulWidget {
  const ChatListPage({
    super.key,
    required this.entry,
    required this.isBot,
    required this.tint,
    required this.onOpen,
  });

  final LensEntry entry;
  final bool isBot;
  final Color? tint;
  final void Function(td.Chat chat) onOpen;

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> with AutomaticKeepAliveClientMixin {
  late final ChatListCubit _cubit = ChatListCubit(
    repository: context.read<ChatsRepository>(),
    prefs: context.read<AppPreferences>(),
    list: widget.entry.list,
  )..start();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Widget _empty(BuildContext context) {
    final e = widget.entry;
    final edit = e.folderId == null ? null : ChatListExtensions.of(context).editFolder(context, e);
    final text = widget.isBot
        ? 'No chats yet. Chats appear here when someone messages your bot.'
        : e.isArchive
        ? 'No archived chats'
        : e.isMain
        ? 'No chats yet. Tap the orb to start one.'
        : 'No chats in ${e.title} yet';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: GlowColors.textMuted),
            ),
            if (edit != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: edit,
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Edit folder'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<ChatListCubit, ChatListState>(
        builder: (context, state) {
          if (state.chats.isEmpty) {
            return state.loading
                ? const Center(child: CircularProgressIndicator(color: GlowColors.violet))
                : _empty(context);
          }
          return LuminousRefresh(
            onRefresh: _cubit.refresh,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 600) _cubit.loadMore();
                return false;
              },
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 120),
                itemCount: state.chats.length,
                itemBuilder: (context, i) {
                  final chat = state.chats[i];
                  return TimelineChatRow(
                    key: ValueKey(chat.id),
                    chat: chat,
                    isFirst: i == 0,
                    isLast: i == state.chats.length - 1,
                    showPresence: !widget.isBot,
                    tint: widget.tint,
                    onTap: () => widget.onOpen(chat),
                    onLongPress: () => showChatActions(context, chat, list: widget.entry.list),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
