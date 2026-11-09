import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/storage/app_preferences.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/chat_scrolling.dart';
import '../../../../core/widgets/luminous_refresh.dart';
import '../../bloc/chat_list_cubit.dart';
import '../../data/chats_repository.dart';
import '../../domain/lens_entry.dart';
import 'chat_actions_sheet.dart';
import 'chat_swipe.dart';
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

  /// The last row built per chat, with what it showed. Handing Flutter the
  /// same widget again skips that row entirely, so a list update rebuilds
  /// only the rows that changed instead of every visible one.
  final _rows = <int, (Object, Widget)>{};

  /// Everything a row reads: the chat (a new object on every change), its
  /// peer (presence), who is typing there, and where it sits.
  Object _signature(BuildContext context, td.Chat chat, int i, int count) {
    final cache = context.read<TelegramCache>();
    final typing = cache.actionsIn(chat.id);
    return (
      _Same(chat),
      _Same(cache.peerUser(chat)),
      typing.isEmpty ? '' : typing.map((a) => '${a.sender}${a.action.runtimeType}').join(),
      i == 0,
      i == count - 1,
      widget.tint,
      widget.isBot,
      // Folder tags, and "13:58" turning into "Yesterday".
      _Same(cache.chatFolders),
      DateTime.now().day,
    );
  }

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
                // Row pulses (and other ambient motion) hold while it moves.
                if (n is ScrollStartNotification && n.depth == 0) ChatScrolling.set(true);
                if (n is ScrollEndNotification && n.depth == 0) ChatScrolling.set(false);
                return false;
              },
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 120),
                // Rows are a fixed 72 dp: no child layout to place them.
                itemExtent: TimelineChatRow.height,
                itemCount: state.chats.length,
                itemBuilder: (context, i) {
                  final chat = state.chats[i];
                  final sig = _signature(context, chat, i, state.chats.length);
                  if (_rows[chat.id] case (final old, final row) when old == sig) return row;
                  final row = SwipeableChatRow(
                    key: ValueKey(chat.id),
                    chat: chat,
                    list: widget.entry.list,
                    child: TimelineChatRow(
                      chat: chat,
                      isFirst: i == 0,
                      isLast: i == state.chats.length - 1,
                      showPresence: !widget.isBot,
                      tint: widget.tint,
                      onTap: () => widget.onOpen(chat),
                      onLongPress: () => showChatActions(
                        context,
                        chat,
                        list: widget.entry.list,
                        onOpen: () => widget.onOpen(chat),
                      ),
                    ),
                  );
                  _rows[chat.id] = (sig, row);
                  return row;
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Compares by identity (TDLib objects are replaced, never mutated).
class _Same {
  const _Same(this.value);

  final Object? value;

  @override
  bool operator ==(Object other) => other is _Same && identical(other.value, value);

  @override
  int get hashCode => identityHashCode(value);
}
